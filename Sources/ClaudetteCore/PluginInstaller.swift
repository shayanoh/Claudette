import Foundation

public enum PluginInstallError: Error, Equatable {
  case invalidPort
}

/// Generates the Claude Code plugin that forwards hook events to the app's loopback server.
public enum PluginInstaller {
  /// Hook events we listen to. WorktreeCreate/WorktreeRemove are deliberately absent: a
  /// WorktreeCreate hook replaces Claude Code's default git behaviour.
  public static let events: [String] = [
    "SessionStart", "SessionEnd", "UserPromptSubmit", "UserPromptExpansion", "Stop",
    "StopFailure", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
    "PermissionDenied", "SubagentStart", "SubagentStop", "TaskCreated", "TaskCompleted",
    "PreCompact", "PostCompact", "PreModelSwitch", "PostModelSwitch", "InstructionsLoaded",
    "Notification", "Elicitation",
  ]

  public static func hooksJSON(port: Int) -> Data {
    let handler: [String: Any] = [
      "type": "http", "url": "http://127.0.0.1:\(port)/hook", "timeout": 2,
    ]
    var map: [String: Any] = [:]
    for event in events { map[event] = [["hooks": [handler]]] }
    let root: [String: Any] = [
      "description": "Claudette: forwards Claude Code activity to the Claudette menubar app",
      "hooks": map,
    ]
    // Dictionaries of plain JSON values always serialise; failure would be a programming error.
    return try! JSONSerialization.data(
      withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
  }

  public static func write(to dir: URL, port: Int) throws {
    guard (1...65535).contains(port) else { throw PluginInstallError.invalidPort }
    let fm = FileManager.default
    try fm.createDirectory(
      at: dir.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
    try fm.createDirectory(
      at: dir.appendingPathComponent("hooks"), withIntermediateDirectories: true)
    let manifest: [String: Any] = [
      "name": "claudette",
      "version": ClaudetteCore.version,
      "description": "Sends Claude Code activity to the Claudette menubar app (localhost only).",
    ]
    let manifestData = try JSONSerialization.data(
      withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try manifestData.write(
      to: dir.appendingPathComponent(".claude-plugin/plugin.json"), options: .atomic)
    try hooksJSON(port: port).write(
      to: dir.appendingPathComponent("hooks/hooks.json"), options: .atomic)
  }
}
