import Foundation

public enum HookDecodeError: Error, Equatable {
  case notAnObject
  case missingEventName
  case missingSessionID
}

/// One Claude Code hook invocation, decoded defensively (unknown fields are kept in `raw`).
public struct HookEvent: Equatable, Sendable {
  public let name: String
  public let sessionID: String
  public let cwd: String?
  public let transcriptPath: String?
  public let agentID: String?
  public let agentType: String?
  public let toolName: String?
  public let toolUseID: String?
  public let mcpServerName: String?
  public let notificationType: String?
  public let errorType: String?
  public let toolInput: JSONValue?
  public let raw: JSONValue

  public static func decode(_ data: Data) throws -> HookEvent {
    let raw = try JSONDecoder().decode(JSONValue.self, from: data)
    guard case .object = raw else { throw HookDecodeError.notAnObject }
    guard let name = raw["hook_event_name"]?.stringValue, !name.isEmpty else {
      throw HookDecodeError.missingEventName
    }
    guard let sessionID = raw["session_id"]?.stringValue, !sessionID.isEmpty else {
      throw HookDecodeError.missingSessionID
    }
    let toolName = raw["tool_name"]?.stringValue
    let server = raw["mcp_server"]?["name"]?.stringValue ?? toolName.flatMap(mcpServer(in:))
    return HookEvent(
      name: name,
      sessionID: sessionID,
      cwd: raw["cwd"]?.stringValue,
      transcriptPath: raw["transcript_path"]?.stringValue,
      agentID: raw["agent_id"]?.stringValue,
      agentType: raw["agent_type"]?.stringValue,
      toolName: toolName,
      toolUseID: raw["tool_use_id"]?.stringValue,
      mcpServerName: server,
      notificationType: raw["notification_type"]?.stringValue,
      // Real StopFailure payloads use `error`; `error_type` is kept as a fallback.
      errorType: raw["error"]?.stringValue ?? raw["error_type"]?.stringValue,
      toolInput: raw["tool_input"],
      raw: raw)
  }

  /// `mcp__<server>__<tool>` gives `<server>`; anything else gives nil.
  static func mcpServer(in toolName: String) -> String? {
    let parts = toolName.components(separatedBy: "__")
    guard parts.count >= 3, parts[0] == "mcp", !parts[1].isEmpty else { return nil }
    return parts[1]
  }
}
