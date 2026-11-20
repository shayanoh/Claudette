import Foundation
import Testing

@testable import ClaudetteCore

private final class Clock: @unchecked Sendable {
  var now = Date(timeIntervalSince1970: 1_700_000_000)
  func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

private func make() -> (SessionStore, Clock) {
  let clock = Clock()
  return (SessionStore(now: { clock.now }), clock)
}

private func ev(
  _ name: String, session: String = "s1", tool: String? = nil, id: String? = nil,
  input: String = "{}", extra: String = ""
) -> HookEvent {
  var parts = [#""hook_event_name":"\#(name)""#, #""session_id":"\#(session)""#]
  if let tool { parts.append(#""tool_name":"\#(tool)""#) }
  if let id { parts.append(#""tool_use_id":"\#(id)""#) }
  parts.append(#""tool_input":\#(input)"#)
  if !extra.isEmpty { parts.append(extra) }
  return try! HookEvent.decode(Data("{\(parts.joined(separator: ","))}".utf8))
}

private func status(_ session: String = "s1", model: String? = nil, ctx: Double? = nil)
  -> StatusPayload
{
  StatusPayload(
    sessionID: session, cwd: nil, modelDisplayName: model, contextUsedPercentage: ctx,
    totalCostUSD: nil, fiveHour: nil, sevenDay: nil)
}

@Test func sessionStartCreatesIdleSession() {
  let (s, _) = make()
  let changes = s.apply(ev("SessionStart", extra: #""cwd":"/p""#))
  #expect(changes.contains(.started("s1")))
  #expect(s.sessions["s1"]?.phase == .idle)
  #expect(s.sessions["s1"]?.cwd == "/p")
}

@Test func duplicateSessionStartIsIdempotent() {
  let (s, _) = make()
  _ = s.apply(ev("SessionStart"))
  let again = s.apply(ev("SessionStart"))
  #expect(!again.contains(.started("s1")))
  #expect(s.sessions.count == 1)
}

@Test func eventForUnknownSessionAutoCreatesIt() {
  let (s, _) = make()
  let changes = s.apply(ev("PreToolUse", tool: "Read", id: "t1"))
  #expect(changes.contains(.started("s1")))
  #expect(s.sessions["s1"]?.phase == .working)
}

@Test func preThenPostToolTogglesWorking() {
  let (s, _) = make()
  let a = s.apply(ev("PreToolUse", tool: "Read", id: "t1", input: #"{"file_path":"/a/b.ts"}"#))
  #expect(s.sessions["s1"]?.phase == .working)
  #expect(
    a.contains {
      if case .toolStarted("s1", let t) = $0 { return t.toolUseID == "t1" } else { return false }
    })
  let b = s.apply(ev("PostToolUse", tool: "Read", id: "t1"))
  #expect(b.contains(.toolFinished("s1", toolUseID: "t1", success: true)))
  #expect(s.sessions["s1"]?.phase == .idle)
}

@Test func postToolUseFailureReportsFailure() {
  let (s, _) = make()
  _ = s.apply(ev("PreToolUse", tool: "Bash", id: "t1"))
  let b = s.apply(ev("PostToolUseFailure", tool: "Bash", id: "t1"))
  #expect(b.contains(.toolFinished("s1", toolUseID: "t1", success: false)))
}

@Test func postWithoutPreIsIgnored() {
  let (s, _) = make()
  _ = s.apply(ev("SessionStart"))
  let b = s.apply(ev("PostToolUse", tool: "Read", id: "ghost"))
  #expect(b.isEmpty)
  #expect(s.sessions["s1"]?.activeTools.isEmpty == true)
}

@Test func overlappingToolsStayWorkingUntilAllDone() {
  let (s, _) = make()
  _ = s.apply(ev("PreToolUse", tool: "Read", id: "a"))
  _ = s.apply(ev("PreToolUse", tool: "Grep", id: "b"))
  _ = s.apply(ev("PostToolUse", tool: "Read", id: "a"))
  #expect(s.sessions["s1"]?.phase == .working)
  _ = s.apply(ev("PostToolUse", tool: "Grep", id: "b"))
  #expect(s.sessions["s1"]?.phase == .idle)
}

@Test func promptKeepsWorkingBetweenToolsUntilStop() {
  let (s, _) = make()
  _ = s.apply(ev("UserPromptSubmit"))
  _ = s.apply(ev("PreToolUse", tool: "Read", id: "a"))
  _ = s.apply(ev("PostToolUse", tool: "Read", id: "a"))
  #expect(s.sessions["s1"]?.phase == .working)
  _ = s.apply(ev("Stop"))
  #expect(s.sessions["s1"]?.phase == .idle)
}

@Test func permissionRequestSetsNeedsApprovalAndNextPostToolClears() {
  let (s, _) = make()
  _ = s.apply(ev("PreToolUse", tool: "Write", id: "w"))
  let c = s.apply(ev("PermissionRequest", tool: "Write"))
  #expect(c.contains(.phaseChanged("s1", .needsApproval)))
  #expect(s.sessions["s1"]?.phase == .needsApproval)
  _ = s.apply(ev("PostToolUse", tool: "Write", id: "w"))
  #expect(s.sessions["s1"]?.phase == .idle)
}

@Test func permissionDeniedClearsNeedsApproval() {
  let (s, _) = make()
  _ = s.apply(ev("PermissionRequest", tool: "Write"))
  _ = s.apply(ev("PermissionDenied", tool: "Write"))
  #expect(s.sessions["s1"]?.phase == .idle)
}

@Test func notificationsMapToApprovalAndQuestion() {
  let (s, _) = make()
  _ = s.apply(ev("Notification", extra: #""notification_type":"permission_prompt""#))
  #expect(s.sessions["s1"]?.phase == .needsApproval)
  _ = s.apply(ev("Stop"))
  _ = s.apply(ev("Notification", extra: #""notification_type":"elicitation_dialog""#))
  #expect(s.sessions["s1"]?.phase == .hasQuestion)
  _ = s.apply(ev("Stop"))
  _ = s.apply(ev("Elicitation"))
  #expect(s.sessions["s1"]?.phase == .hasQuestion)
  _ = s.apply(ev("Stop"))
  _ = s.apply(ev("Notification", extra: #""notification_type":"idle_prompt""#))
  #expect(s.sessions["s1"]?.phase == .idle)
}

@Test func stopFailureMapsErrorKinds() {
  let cases: [(String, ErrorKind)] = [
    ("rate_limit", .rateLimit), ("authentication_failed", .auth), ("billing_error", .billing),
    ("server_error", .api), ("something_new", .unknown),
  ]
  for (raw, kind) in cases {
    let (s, _) = make()
    _ = s.apply(ev("UserPromptSubmit"))
    _ = s.apply(ev("StopFailure", extra: #""error_type":"\#(raw)""#))
    #expect(s.sessions["s1"]?.phase == .error(kind), "\(raw)")
  }
  let (s, _) = make()
  _ = s.apply(ev("StopFailure"))  // no error key at all
  #expect(s.sessions["s1"]?.phase == .error(.unknown))
  _ = s.apply(ev("UserPromptSubmit"))  // next turn clears the error
  #expect(s.sessions["s1"]?.phase == .working)
}

@Test func subagentStartStopTracksAndUnknownStopIgnored() {
  let (s, _) = make()
  let a = s.apply(ev("SubagentStart", extra: #""agent_id":"a1","agent_type":"Explore""#))
  #expect(a.contains(.subagentStarted("s1", agentID: "a1")))
  #expect(s.sessions["s1"]?.subagents == ["a1"])
  let ghost = s.apply(ev("SubagentStop", extra: #""agent_id":"zzz""#))
  #expect(!ghost.contains { if case .subagentStopped = $0 { return true } else { return false } })
  let b = s.apply(ev("SubagentStop", extra: #""agent_id":"a1""#))
  #expect(b.contains(.subagentStopped("s1", agentID: "a1")))
  #expect(s.sessions["s1"]?.subagents.isEmpty == true)
}

@Test func longShellEmittedOnceAfter10sWithoutPost() {
  let (s, c) = make()
  _ = s.apply(ev("PreToolUse", tool: "Bash", id: "b1", input: #"{"command":"sleep 30"}"#))
  c.advance(9)
  #expect(s.tick().isEmpty)
  c.advance(2)
  #expect(s.tick() == [.longShell("s1", toolUseID: "b1")])
  #expect(s.tick().isEmpty)
}

@Test func backgroundBashFlagsIsBackgroundAndNeverLongShellTimer() {
  let (s, c) = make()
  _ = s.apply(
    ev("PreToolUse", tool: "Bash", id: "b1", input: #"{"command":"x","run_in_background":true}"#))
  #expect(s.sessions["s1"]?.activeTools.first?.isBackground == true)
  c.advance(60)
  #expect(!s.tick().contains(.longShell("s1", toolUseID: "b1")))
}

@Test func staleSleepsAt15MinAndRemovedAt60() {
  let (s, c) = make()
  _ = s.apply(ev("SessionStart"))
  c.advance(14 * 60)
  #expect(s.tick().isEmpty)
  c.advance(2 * 60)
  #expect(s.tick() == [.phaseChanged("s1", .sleeping)])
  #expect(s.sessions["s1"]?.phase == .sleeping)
  c.advance(44 * 60 + 1)
  #expect(s.tick() == [.ended("s1")])
  #expect(s.sessions["s1"] == nil)
}

@Test func eventWakesASleepingSession() {
  let (s, c) = make()
  _ = s.apply(ev("SessionStart"))
  c.advance(16 * 60)
  _ = s.tick()
  let w = s.apply(ev("UserPromptSubmit"))
  #expect(w.contains(.phaseChanged("s1", .working)))
}

@Test func sessionEndRemovesAndLateEventsDoNotResurrect() {
  let (s, c) = make()
  _ = s.apply(ev("SessionStart"))
  #expect(s.apply(ev("SessionEnd")).contains(.ended("s1")))
  #expect(s.sessions["s1"] == nil)
  #expect(s.apply(ev("Stop")).isEmpty)  // late event right after the end
  #expect(s.applyStatus(status()).isEmpty)  // late status line tick
  #expect(s.sessions["s1"] == nil)
  _ = s.apply(ev("SessionStart", extra: #""source":"resume""#))  // a resume is allowed
  #expect(s.sessions["s1"] != nil)
  _ = c
}

@Test func sessionEndForUnknownSessionIsIgnored() {
  let (s, _) = make()
  #expect(s.apply(ev("SessionEnd", session: "never-seen")).isEmpty)
}

@Test func skillToolCallEmitsSkillLoaded() {
  let (s, _) = make()
  let c = s.apply(
    ev("PreToolUse", tool: "Skill", id: "k", input: #"{"skill":"superpowers:brainstorming"}"#))
  #expect(c.contains(.skillLoaded("s1", name: "superpowers:brainstorming")))
}

@Test func userPromptExpansionEmitsSkillLoaded() {
  let (s, _) = make()
  let c = s.apply(ev("UserPromptExpansion", extra: #""command_name":"review""#))
  #expect(c.contains(.skillLoaded("s1", name: "review")))
}

@Test func preCompactEmitsCompacted() {
  let (s, _) = make()
  #expect(s.apply(ev("PreCompact")).contains(.compacted("s1")))
}

@Test func statusPayloadUpdatesModelAndContext() {
  let (s, _) = make()
  _ = s.apply(ev("SessionStart"))
  let c = s.applyStatus(status(model: "Opus", ctx: 42))
  #expect(c.contains(.modelChanged("s1", "Opus")))
  #expect(s.sessions["s1"]?.model == "Opus")
  #expect(s.sessions["s1"]?.contextUsedPercentage == 42)
  #expect(!s.applyStatus(status(model: "Opus", ctx: 43)).contains(.modelChanged("s1", "Opus")))
}

@Test func twoSessionsAreIndependent() {
  let (s, _) = make()
  _ = s.apply(ev("PreToolUse", session: "a", tool: "Read", id: "1"))
  _ = s.apply(ev("SessionStart", session: "b"))
  #expect(s.sessions["a"]?.phase == .working)
  #expect(s.sessions["b"]?.phase == .idle)
}
