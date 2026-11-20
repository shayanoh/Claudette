import Foundation
import Testing

@testable import ClaudetteCore

private func data(_ json: String) -> Data { Data(json.utf8) }

@Test func decodesPreToolUseWithMcpServer() throws {
  let e = try HookEvent.decode(
    data(
      """
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/p",
       "tool_name":"mcp__github__create_issue","tool_use_id":"t1",
       "tool_input":{"title":"x"},"mcp_server":{"name":"github","source":"user"}}
      """))
  #expect(e.name == "PreToolUse")
  #expect(e.sessionID == "s1")
  #expect(e.cwd == "/p")
  #expect(e.toolName == "mcp__github__create_issue")
  #expect(e.toolUseID == "t1")
  #expect(e.mcpServerName == "github")
  #expect(e.toolInput?["title"]?.stringValue == "x")
}

@Test func decodesSubagentFields() throws {
  let e = try HookEvent.decode(
    data(
      """
      {"hook_event_name":"SubagentStart","session_id":"s1","agent_id":"a9","agent_type":"Explore"}
      """))
  #expect(e.agentID == "a9")
  #expect(e.agentType == "Explore")
}

@Test func decodesNotificationType() throws {
  let e = try HookEvent.decode(
    data(
      """
      {"hook_event_name":"Notification","session_id":"s1","notification_type":"permission_prompt","message":"m"}
      """))
  #expect(e.notificationType == "permission_prompt")
}

@Test func decodesErrorType() throws {
  let e = try HookEvent.decode(
    data(
      """
      {"hook_event_name":"StopFailure","session_id":"s1","error_type":"rate_limit"}
      """))
  #expect(e.errorType == "rate_limit")
}

@Test func rejectsNonObject() {
  #expect(throws: HookDecodeError.notAnObject) { try HookEvent.decode(data("[1,2]")) }
  #expect(throws: (any Error).self) { try HookEvent.decode(data("not json")) }
  #expect(throws: (any Error).self) { try HookEvent.decode(Data()) }
}

@Test func rejectsMissingSessionID() {
  #expect(throws: HookDecodeError.missingSessionID) {
    try HookEvent.decode(data(#"{"hook_event_name":"Stop"}"#))
  }
}

@Test func rejectsMissingEventName() {
  #expect(throws: HookDecodeError.missingEventName) {
    try HookEvent.decode(data(#"{"session_id":"s1"}"#))
  }
}

@Test func ignoresUnknownFields() throws {
  let e = try HookEvent.decode(
    data(#"{"hook_event_name":"Stop","session_id":"s1","brand_new":{"x":[1,2,3]}}"#))
  #expect(e.name == "Stop")
  #expect(e.raw["brand_new"] != nil)
}

@Test func fallsBackToToolNamePrefixForMcpServer() throws {
  let e = try HookEvent.decode(
    data(
      #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"mcp__memory__create_entities"}"#
    ))
  #expect(e.mcpServerName == "memory")
}

@Test func pluginMcpToolNameKeepsServerSegment() throws {
  let e = try HookEvent.decode(
    data(
      #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"mcp__plugin_figma_figma__get_design_context"}"#
    ))
  #expect(e.mcpServerName == "plugin_figma_figma")
}

@Test func nonMcpToolHasNoServer() throws {
  let e = try HookEvent.decode(
    data(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Read"}"#))
  #expect(e.mcpServerName == nil)
}

@Test func decodesTheRealStopFailureErrorField() throws {
  // Captured from a real Claude Code 2.1.329 session (not logged in).
  let e = try HookEvent.decode(
    Data(
      #"{"hook_event_name":"StopFailure","session_id":"s1","error":"authentication_failed","last_assistant_message":"Not logged in"}"#
        .utf8))
  #expect(e.errorType == "authentication_failed")
}
