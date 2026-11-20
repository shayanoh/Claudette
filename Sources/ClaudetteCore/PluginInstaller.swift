import Foundation

public enum PluginInstallError: Error, Equatable {
  case invalidPort
  case notOurs
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

  /// Hooks run this script instead of `http` handlers: an `http` hook reports an error in Claude
  /// Code whenever the app is closed, a script that always exits 0 never does.
  public static func hooksJSON(port: Int, scriptPath: String) -> Data {
    let handler: [String: Any] = [
      "type": "command", "command": shellQuote(scriptPath), "timeout": 5,
    ]
    var map: [String: Any] = [:]
    for event in events { map[event] = [["hooks": [handler]]] }
    let root: [String: Any] = [
      "description": "Claudette: forwards Claude Code activity to the Claudette menubar app",
      "hooks": map,
    ]
    // Dictionaries of plain JSON values always serialise; failure would be a programming error.
    return try! JSONSerialization.data(
      withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }

  /// Reads the event, posts it in a detached background `curl`, and always exits 0. Command hooks
  /// block Claude Code until they exit, so nothing here may wait on the network.
  public static func hookScript(port: Int) -> String {
    """
    #!/bin/sh
    # Claudette hook forwarder: never fails, never blocks, prints nothing.
    body=$(cat)
    ( printf '%s' "$body" | curl -s -m 2 --connect-timeout 1 -X POST \
      -H 'Content-Type: application/json' --data-binary @- \
      "http://127.0.0.1:\(port)/hook" >/dev/null 2>&1 & ) >/dev/null 2>&1
    exit 0

    """
  }

  static func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// `~/.claude/skills/claudette`: Claude Code loads a plugin saved here with no install step.
  public static var defaultPluginDir: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      ".claude/skills/claudette")
  }

  public static func isInstalled(pluginDir: URL) -> Bool {
    guard
      let data = try? Data(
        contentsOf: pluginDir.appendingPathComponent(".claude-plugin/plugin.json")),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return obj["name"] as? String == "claudette"
  }

  /// An install whose hooks are the old noisy `http` handlers (offered an update in Settings).
  public static func isLegacy(pluginDir: URL) -> Bool {
    guard isInstalled(pluginDir: pluginDir),
      let text = try? String(
        contentsOf: pluginDir.appendingPathComponent("hooks/hooks.json"), encoding: .utf8)
    else { return false }
    return text.contains("\"type\" : \"http\"") || text.contains("\"type\":\"http\"")
  }

  /// Writes (or updates) the plugin. Refuses to touch a non-empty directory that is not ours.
  public static func install(pluginDir: URL, port: Int) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: pluginDir.path), !isInstalled(pluginDir: pluginDir) {
      let contents = (try? fm.contentsOfDirectory(atPath: pluginDir.path)) ?? ["?"]
      guard contents.isEmpty else { throw PluginInstallError.notOurs }
    }
    try write(to: pluginDir, port: port)
  }

  /// Removes the plugin directory, but only if it is ours.
  public static func uninstall(pluginDir: URL) throws {
    guard FileManager.default.fileExists(atPath: pluginDir.path) else { return }
    guard isInstalled(pluginDir: pluginDir) else { throw PluginInstallError.notOurs }
    try FileManager.default.removeItem(at: pluginDir)
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
      withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try manifestData.write(
      to: dir.appendingPathComponent(".claude-plugin/plugin.json"), options: .atomic)
    let script = dir.appendingPathComponent("hooks/post.sh")
    try Data(hookScript(port: port).utf8).write(to: script, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    try hooksJSON(port: port, scriptPath: script.path).write(
      to: dir.appendingPathComponent("hooks/hooks.json"), options: .atomic)
  }
}
