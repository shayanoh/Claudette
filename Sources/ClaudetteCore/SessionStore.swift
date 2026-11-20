import Foundation

public enum ErrorKind: Equatable, Sendable {
  case api, auth, billing, rateLimit, disconnect, unknown
}

public enum SessionPhase: Equatable, Sendable {
  case sleeping, idle, working, needsApproval, hasQuestion
  case error(ErrorKind)
}

public struct ToolActivity: Equatable, Sendable {
  public let toolUseID: String
  public let toolName: String
  public let mcpServer: String?
  public let input: JSONValue?
  public let startedAt: Date
  public let isBackground: Bool
  /// Set for tool calls made inside a sub-agent.
  public var agentID: String? = nil
}

/// How a tool call ended; `summary` is at most the last 200 characters of its output or error.
public struct ToolResult: Equatable, Sendable {
  public var success: Bool
  public var durationMs: Int?
  public var summary: String?

  public init(success: Bool, durationMs: Int?, summary: String?) {
    self.success = success
    self.durationMs = durationMs
    self.summary = summary
  }

  static let summaryLimit = 200

  /// Bash output lives in `tool_response.stdout`/`stderr`, failures in `error` (see
  /// docs/spikes/payloads.md); other tools have no text we trust, so they give no summary.
  static func from(_ e: HookEvent, success: Bool) -> ToolResult {
    var text = e.raw["error"]?.stringValue
    if text == nil, let r = e.raw["tool_response"] {
      for key in ["stdout", "stderr"] {
        if let t = r[key]?.stringValue, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          text = t
          break
        }
      }
    }
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    let summary = trimmed.flatMap { $0.isEmpty ? nil : String($0.suffix(summaryLimit)) }
    // Clamp before converting: Int(_:) traps on huge or non-finite doubles.
    let duration = e.raw["duration_ms"]?.doubleValue.flatMap {
      $0.isFinite ? Int(max(0, min($0, 1e9))) : nil
    }
    return ToolResult(success: success, durationMs: duration, summary: summary)
  }
}

public struct SessionState: Equatable, Sendable {
  public let id: String
  public var cwd: String?
  public var phase: SessionPhase
  public var activeTools: [ToolActivity]
  public var subagents: Set<String>
  public var model: String?
  public var contextUsedPercentage: Double?
  /// A turn is running but no tool is active and nothing waits for the user.
  public var isThinking = false
  public let startedAt: Date
  public var lastEventAt: Date
}

public enum SessionChange: Equatable, Sendable {
  case started(String)
  case ended(String)
  case phaseChanged(String, SessionPhase)
  case toolStarted(String, ToolActivity)
  case toolFinished(String, toolUseID: String, success: Bool)
  case toolResult(String, toolUseID: String, ToolResult)
  case thinkingChanged(String, Bool)
  case longShell(String, toolUseID: String)
  case subagentStarted(String, agentID: String)
  case subagentStopped(String, agentID: String)
  case compacted(String)
  case skillLoaded(String, name: String)
  case modelChanged(String, String)
}

/// Per-session state machines fed by hook events and status line payloads. Not thread-safe:
/// use from one queue (main).
public final class SessionStore {
  public static let longShellAfter: TimeInterval = 10
  public static let sleepAfter: TimeInterval = 15 * 60
  public static let removeAfter: TimeInterval = 60 * 60
  static let lateEventWindow: TimeInterval = 60
  /// More sessions than this are ignored (a flood of junk must not fill the screen).
  public static let maxSessions = 64

  private struct Entry {
    var state: SessionState
    var turnActive = false
    var attention: SessionPhase?  // needsApproval, hasQuestion or error
    var asleep = false
    var announcedLong: Set<String> = []
  }

  private let now: () -> Date
  private var entries: [String: Entry] = [:]
  private var endedAt: [String: Date] = [:]

  public init(now: @escaping () -> Date) {
    self.now = now
  }

  public var sessions: [String: SessionState] { entries.mapValues(\.state) }

  // MARK: - Hook events

  public func apply(_ e: HookEvent) -> [SessionChange] {
    let t = now()
    let id = e.sessionID
    pruneEnded(t)
    if e.name == "SessionEnd" {
      guard entries[id] != nil else { return [] }
      entries[id] = nil
      endedAt[id] = t
      return [.ended(id)]
    }
    if e.name == "SessionStart" {
      endedAt[id] = nil
    } else if endedAt[id] != nil {
      return []  // a late event from a session that just ended
    }

    var changes: [SessionChange] = []
    if entries[id] == nil {
      guard entries.count < Self.maxSessions else { return [] }
      entries[id] = Entry(
        state: SessionState(
          id: id, cwd: e.cwd, phase: .idle, activeTools: [], subagents: [], model: nil,
          contextUsedPercentage: nil, startedAt: t, lastEventAt: t))
      changes.append(.started(id))
    }
    entries[id]!.state.lastEventAt = t
    entries[id]!.asleep = false
    if entries[id]!.state.cwd == nil { entries[id]!.state.cwd = e.cwd }

    switch e.name {
    case "SessionStart":
      if let m = e.raw["model"]?.stringValue { entries[id]!.state.model = m }
    case "UserPromptSubmit":
      entries[id]!.turnActive = true
      entries[id]!.attention = nil
    case "UserPromptExpansion":
      let name =
        e.raw["command_name"]?.stringValue ?? e.raw["name"]?.stringValue ?? "command"
      changes.append(.skillLoaded(id, name: name))
    case "PreToolUse":
      changes += toolStarted(e, id: id, at: t)
    case "PostToolUse", "PostToolUseFailure":
      changes += toolFinished(e, id: id, success: e.name == "PostToolUse")
    case "PermissionRequest":
      entries[id]!.attention = .needsApproval
    case "PermissionDenied":
      if entries[id]!.attention == .needsApproval { entries[id]!.attention = nil }
    case "Notification":
      switch e.notificationType {
      case "permission_prompt": entries[id]!.attention = .needsApproval
      case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
        entries[id]!.attention = .hasQuestion
      default: break
      }
    case "Elicitation":
      entries[id]!.attention = .hasQuestion
    case "Stop":
      entries[id]!.turnActive = false
      entries[id]!.attention = nil
      changes += finishAllTools(id: id, success: true)
    case "StopFailure":
      entries[id]!.turnActive = false
      entries[id]!.attention = .error(Self.errorKind(e.errorType))
      changes += finishAllTools(id: id, success: false)
    case "SubagentStart":
      if let a = e.agentID, entries[id]!.state.subagents.insert(a).inserted {
        changes.append(.subagentStarted(id, agentID: a))
      }
    case "SubagentStop":
      if let a = e.agentID, entries[id]!.state.subagents.remove(a) != nil {
        changes.append(.subagentStopped(id, agentID: a))
      }
    case "PreCompact":
      changes.append(.compacted(id))
    default:
      break
    }
    refresh(id, &changes)
    return changes
  }

  // MARK: - Status line

  public func applyStatus(_ p: StatusPayload) -> [SessionChange] {
    let t = now()
    pruneEnded(t)
    let id = p.sessionID
    if endedAt[id] != nil { return [] }
    var changes: [SessionChange] = []
    if entries[id] == nil {
      guard entries.count < Self.maxSessions else { return [] }
      entries[id] = Entry(
        state: SessionState(
          id: id, cwd: p.cwd, phase: .idle, activeTools: [], subagents: [], model: nil,
          contextUsedPercentage: nil, startedAt: t, lastEventAt: t))
      changes.append(.started(id))
    }
    entries[id]!.state.lastEventAt = t
    if let c = p.contextUsedPercentage { entries[id]!.state.contextUsedPercentage = c }
    if let m = p.modelDisplayName, m != entries[id]!.state.model {
      entries[id]!.state.model = m
      changes.append(.modelChanged(id, m))
    }
    return changes
  }

  // MARK: - Timers

  /// Call about once a second: long-shell detection, sleeping and removing stale sessions.
  public func tick() -> [SessionChange] {
    let t = now()
    pruneEnded(t)
    var changes: [SessionChange] = []
    for id in entries.keys.sorted() {
      guard var entry = entries[id] else { continue }
      for tool in entry.state.activeTools
      where tool.toolName == "Bash" && !tool.isBackground
        && t.timeIntervalSince(tool.startedAt) >= Self.longShellAfter
        && !entry.announcedLong.contains(tool.toolUseID)
      {
        entry.announcedLong.insert(tool.toolUseID)
        changes.append(.longShell(id, toolUseID: tool.toolUseID))
      }
      entries[id] = entry
      let silent = t.timeIntervalSince(entry.state.lastEventAt)
      if silent >= Self.removeAfter, entry.attention == nil {  // never drop one that is waiting for you
        entries[id] = nil
        endedAt[id] = t
        changes.append(.ended(id))
      } else if silent >= Self.sleepAfter, !entry.asleep, entry.state.activeTools.isEmpty,
        !entry.turnActive
      {
        entries[id]!.asleep = true
        refresh(id, &changes)
      }
    }
    return changes
  }

  // MARK: - Helpers

  private func toolStarted(_ e: HookEvent, id: String, at t: Date) -> [SessionChange] {
    guard let name = e.toolName else { return [] }
    var changes: [SessionChange] = []
    let toolID = e.toolUseID ?? UUID().uuidString
    if case .error? = entries[id]!.attention { entries[id]!.attention = nil }
    if !entries[id]!.state.activeTools.contains(where: { $0.toolUseID == toolID }) {
      let tool = ToolActivity(
        toolUseID: toolID, toolName: name, mcpServer: e.mcpServerName, input: e.toolInput,
        startedAt: t, isBackground: e.toolInput?["run_in_background"]?.boolValue == true,
        agentID: e.agentID)
      entries[id]!.state.activeTools.append(tool)
      changes.append(.toolStarted(id, tool))
    }
    if name == "Skill" {
      changes.append(.skillLoaded(id, name: e.toolInput?["skill"]?.stringValue ?? ""))
    }
    return changes
  }

  private func toolFinished(_ e: HookEvent, id: String, success: Bool) -> [SessionChange] {
    guard let toolID = e.toolUseID,
      let i = entries[id]!.state.activeTools.firstIndex(where: { $0.toolUseID == toolID })
    else { return [] }
    entries[id]!.state.activeTools.remove(at: i)
    entries[id]!.announcedLong.remove(toolID)
    if let a = entries[id]!.attention, a == .needsApproval || a == .hasQuestion {
      entries[id]!.attention = nil
    }
    return [
      .toolFinished(id, toolUseID: toolID, success: success),
      .toolResult(id, toolUseID: toolID, ToolResult.from(e, success: success)),
    ]
  }

  private func finishAllTools(id: String, success: Bool) -> [SessionChange] {
    let left = entries[id]!.state.activeTools
    entries[id]!.state.activeTools = []
    entries[id]!.announcedLong = []
    return left.map { .toolFinished(id, toolUseID: $0.toolUseID, success: success) }
  }

  private func refresh(_ id: String, _ changes: inout [SessionChange]) {
    guard let entry = entries[id] else { return }
    let phase: SessionPhase
    if let a = entry.attention {
      phase = a
    } else if entry.turnActive || !entry.state.activeTools.isEmpty {
      phase = .working
    } else if entry.asleep {
      phase = .sleeping
    } else {
      phase = .idle
    }
    if phase != entry.state.phase {
      entries[id]!.state.phase = phase
      changes.append(.phaseChanged(id, phase))
    }
    let thinking = entry.turnActive && entry.state.activeTools.isEmpty && entry.attention == nil
    if thinking != entry.state.isThinking {
      entries[id]!.state.isThinking = thinking
      changes.append(.thinkingChanged(id, thinking))
    }
  }

  private func pruneEnded(_ t: Date) {
    endedAt = endedAt.filter { t.timeIntervalSince($0.value) < Self.lateEventWindow }
  }

  static func errorKind(_ raw: String?) -> ErrorKind {
    switch raw {
    case "rate_limit": return .rateLimit
    case "authentication_failed", "oauth_org_not_allowed": return .auth
    case "billing_error", "account_on_hold": return .billing
    case "server_error", "invalid_request", "model_not_found", "max_output_tokens",
      "cloud_credential_error":
      return .api
    default: return .unknown
    }
  }
}
