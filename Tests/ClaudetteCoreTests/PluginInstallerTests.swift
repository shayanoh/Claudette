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

@Test func writeRejectsInvalidPort() {
  #expect(throws: (any Error).self) {
    try PluginInstaller.write(to: tempDir(), port: 0)
  }
  #expect(throws: (any Error).self) {
    try PluginInstaller.write(to: tempDir(), port: 70000)
  }
}
