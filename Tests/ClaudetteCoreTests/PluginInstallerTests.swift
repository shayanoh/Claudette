import Foundation
import Testing

@testable import ClaudetteCore

private func tempDir() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "claudette-plugin-\(UUID().uuidString)")
}

private func hooks(port: Int = 47631) throws -> [String: [[String: Any]]] {
  let obj = try JSONSerialization.jsonObject(with: PluginInstaller.hooksJSON(port: port))
  let root = try #require(obj as? [String: Any])
  return try #require(root["hooks"] as? [String: [[String: Any]]])
}

@Test func hooksJSONHasWrapperKeyAndAllEvents() throws {
  let h = try hooks()
  for event in PluginInstaller.events { #expect(h[event] != nil, "missing \(event)") }
  #expect(h.count == PluginInstaller.events.count)
  #expect(PluginInstaller.events.contains("PreToolUse"))
  #expect(PluginInstaller.events.contains("StopFailure"))
}

@Test func worktreeHooksAreNeverRegistered() {
  // Docs: a WorktreeCreate hook replaces Claude's default git behaviour, so we must not register it.
  #expect(!PluginInstaller.events.contains("WorktreeCreate"))
  #expect(!PluginInstaller.events.contains("WorktreeRemove"))
}

@Test func everyHandlerIsHttpLoopbackWithTimeout2() throws {
  let h = try hooks(port: 4242)
  for (_, groups) in h {
    for group in groups {
      let handlers = try #require(group["hooks"] as? [[String: Any]])
      #expect(!handlers.isEmpty)
      for handler in handlers {
        #expect(handler["type"] as? String == "http")
        #expect(handler["url"] as? String == "http://127.0.0.1:4242/hook")
        #expect(handler["timeout"] as? Int == 2)
      }
    }
  }
}

@Test func noHandlerSetsAsync() throws {
  let text = String(decoding: PluginInstaller.hooksJSON(port: 1), as: UTF8.self)
  #expect(!text.contains("async"))
}

@Test func writeCreatesManifestAndHooks() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try PluginInstaller.write(to: dir, port: 47631)
  let manifest = try Data(contentsOf: dir.appendingPathComponent(".claude-plugin/plugin.json"))
  let m = try #require(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
  #expect(m["name"] as? String == "claudette")
  #expect(m["version"] as? String == ClaudetteCore.version)
  #expect(
    FileManager.default.fileExists(atPath: dir.appendingPathComponent("hooks/hooks.json").path))
}

@Test func installThenIsInstalledThenUninstall() throws {
  let dir = tempDir().appendingPathComponent("skills/claudette")  // parent does not exist yet
  defer {
    try? FileManager.default.removeItem(
      at: dir.deletingLastPathComponent().deletingLastPathComponent())
  }
  #expect(!PluginInstaller.isInstalled(pluginDir: dir))
  try PluginInstaller.install(pluginDir: dir, port: 47631)
  #expect(PluginInstaller.isInstalled(pluginDir: dir))
  try PluginInstaller.uninstall(pluginDir: dir)
  #expect(!FileManager.default.fileExists(atPath: dir.path))
  #expect(!PluginInstaller.isInstalled(pluginDir: dir))
}

@Test func reinstallUpdatesPortInPlace() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try PluginInstaller.install(pluginDir: dir, port: 1111)
  try PluginInstaller.install(pluginDir: dir, port: 2222)
  let text = try String(contentsOf: dir.appendingPathComponent("hooks/hooks.json"), encoding: .utf8)
  #expect(text.contains(":2222/hook"))
  #expect(!text.contains(":1111/hook"))
}

@Test func installRefusesToOverwriteForeignDirectory() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try FileManager.default.createDirectory(
    at: dir.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
  try Data(#"{"name":"someone-elses"}"#.utf8).write(
    to: dir.appendingPathComponent(".claude-plugin/plugin.json"))
  #expect(throws: PluginInstallError.notOurs) {
    try PluginInstaller.install(pluginDir: dir, port: 47631)
  }
  #expect(!PluginInstaller.isInstalled(pluginDir: dir))
}

@Test func installRefusesNonPluginDirectoryWithFiles() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  try Data("precious".utf8).write(to: dir.appendingPathComponent("notes.txt"))
  #expect(throws: PluginInstallError.notOurs) {
    try PluginInstaller.install(pluginDir: dir, port: 47631)
  }
  #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
}

@Test func uninstallRemovesOnlyOurDirectory() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  try Data("precious".utf8).write(to: dir.appendingPathComponent("notes.txt"))
  #expect(throws: PluginInstallError.notOurs) { try PluginInstaller.uninstall(pluginDir: dir) }
  #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
}

@Test func uninstallOfMissingDirectoryIsANoOp() throws {
  try PluginInstaller.uninstall(pluginDir: tempDir())
}

@Test func defaultPluginDirIsUnderClaudeSkills() {
  #expect(PluginInstaller.defaultPluginDir.path.hasSuffix("/.claude/skills/claudette"))
}

@Test func claudePluginValidatePasses() throws {
  guard
    let claude = [
      "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
      NSHomeDirectory() + "/.local/bin/claude", NSHomeDirectory() + "/.claude/local/claude",
    ]
    .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
  else { return }  // claude CLI not installed here: nothing to validate against
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try PluginInstaller.write(to: dir, port: 47631)
  let p = Process()
  p.executableURL = URL(fileURLWithPath: claude)
  p.arguments = ["plugin", "validate", dir.path]
  p.standardOutput = Pipe()
  p.standardError = Pipe()
  try p.run()
  p.waitUntilExit()
  #expect(p.terminationStatus == 0)
}

@Test func writeRejectsInvalidPort() {
  #expect(throws: (any Error).self) {
    try PluginInstaller.write(to: tempDir(), port: 0)
  }
  #expect(throws: (any Error).self) {
    try PluginInstaller.write(to: tempDir(), port: 70000)
  }
}
