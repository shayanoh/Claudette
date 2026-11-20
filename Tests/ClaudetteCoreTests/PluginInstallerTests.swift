import Foundation
import Testing

@testable import ClaudetteCore

private func tempDir() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "claudette-plugin-\(UUID().uuidString)")
}

private func hooks(port: Int = 47631) throws -> [String: [[String: Any]]] {
  let obj = try JSONSerialization.jsonObject(
    with: PluginInstaller.hooksJSON(port: port, scriptPath: "/x/hooks/post.sh"))
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

@Test func everyHandlerIsTheCommandScript() throws {
  let h = try hooks()
  for (_, groups) in h {
    for group in groups {
      let handlers = try #require(group["hooks"] as? [[String: Any]])
      #expect(!handlers.isEmpty)
      for handler in handlers {
        #expect(handler["type"] as? String == "command")
        #expect((handler["command"] as? String)?.contains("/hooks/post.sh") == true)
        #expect(handler["timeout"] as? Int == 5)
      }
    }
  }
}

@Test func noHandlerSetsAsync() throws {
  let text = String(
    decoding: PluginInstaller.hooksJSON(port: 1, scriptPath: "/x/post.sh"), as: UTF8.self)
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
  let text = try String(contentsOf: dir.appendingPathComponent("hooks/post.sh"), encoding: .utf8)
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

// MARK: - hook script

private struct ScriptRun {
  var status: Int32
  var out: Data
  var err: Data
  var seconds: Double
}

private func runScript(_ script: URL, stdin body: Data) throws -> ScriptRun {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/sh")
  p.arguments = [script.path]
  let inPipe = Pipe()
  let outPipe = Pipe()
  let errPipe = Pipe()
  p.standardInput = inPipe
  p.standardOutput = outPipe
  p.standardError = errPipe
  let start = Date()
  try p.run()
  // Feed stdin off-thread: a 1 MiB body exceeds the pipe buffer.
  let writer = Thread {
    try? inPipe.fileHandleForWriting.write(contentsOf: body)
    try? inPipe.fileHandleForWriting.close()
  }
  writer.start()
  p.waitUntilExit()
  return ScriptRun(
    status: p.terminationStatus,
    out: outPipe.fileHandleForReading.readDataToEndOfFile(),
    err: errPipe.fileHandleForReading.readDataToEndOfFile(),
    seconds: Date().timeIntervalSince(start))
}

private func installed(port: Int) throws -> (dir: URL, script: URL) {
  let dir = tempDir()
  try PluginInstaller.install(pluginDir: dir, port: port)
  return (dir, dir.appendingPathComponent("hooks/post.sh"))
}

@Test func scriptExitsZeroWhenPortClosed() throws {
  let (dir, script) = try installed(port: 1)
  defer { try? FileManager.default.removeItem(at: dir) }
  let body = Data("{\"a\":\"quote\\\" \\n \u{1F600}\"}\n".utf8)
  let r = try runScript(script, stdin: body)
  #expect(r.status == 0)
  #expect(r.out.isEmpty)
  #expect(r.err.isEmpty)
  #expect(r.seconds < 1.5)
}

@Test func scriptExitsZeroOnHugeBody() throws {
  let (dir, script) = try installed(port: 1)
  defer { try? FileManager.default.removeItem(at: dir) }
  let r = try runScript(script, stdin: Data(repeating: UInt8(ascii: "x"), count: 1 << 20))
  #expect(r.status == 0)
  #expect(r.out.isEmpty && r.err.isEmpty)
  #expect(r.seconds < 1.5)
}

private final class Got: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [FeedMessage] = []
  func add(_ m: FeedMessage) {
    lock.lock()
    items.append(m)
    lock.unlock()
  }
  var all: [FeedMessage] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

@Test func scriptDeliversBodyWhenServerListens() async throws {
  let got = Got()
  let server = FeedServer(port: 0) { got.add($0) }
  try server.start()
  defer { server.stop() }
  let port = try #require(server.boundPort)
  let (dir, script) = try installed(port: Int(port))
  defer { try? FileManager.default.removeItem(at: dir) }
  let r = try runScript(
    script, stdin: Data(#"{"hook_event_name":"Stop","session_id":"s9"}"#.utf8))
  #expect(r.status == 0)
  for _ in 0..<40 where got.all.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
  guard case .hook(let e)? = got.all.first else {
    Issue.record("script did not deliver the event")
    return
  }
  #expect(e.sessionID == "s9")
}

@Test func scriptIsExecutable() throws {
  let (dir, script) = try installed(port: 47631)
  defer { try? FileManager.default.removeItem(at: dir) }
  let mode = try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions]
  #expect((mode as? Int ?? 0) & 0o111 != 0)
}

@Test func legacyHttpInstallIsDetected() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try PluginInstaller.install(pluginDir: dir, port: 47631)
  #expect(!PluginInstaller.isLegacy(pluginDir: dir))
  let legacy = #"{"hooks":{"Stop":[{"hooks":[{"type":"http","url":"http://127.0.0.1:1/hook"}]}]}}"#
  try Data(legacy.utf8).write(to: dir.appendingPathComponent("hooks/hooks.json"))
  #expect(PluginInstaller.isLegacy(pluginDir: dir))
  try PluginInstaller.install(pluginDir: dir, port: 47631)
  #expect(!PluginInstaller.isLegacy(pluginDir: dir))
  #expect(!PluginInstaller.isLegacy(pluginDir: tempDir()))  // not installed at all
}

@Test func commandQuotesPathsWithSpacesAndQuotes() throws {
  let dir = tempDir().appendingPathComponent("it's a dir")
  defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let script = dir.appendingPathComponent("post.sh")
  try Data("#!/bin/sh\nprintf ok\n".utf8).write(to: script)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
  let json = PluginInstaller.hooksJSON(port: 1, scriptPath: script.path)
  let root = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
  let hooks = try #require(root["hooks"] as? [String: [[String: Any]]])
  let handler = try #require((hooks["Stop"]?.first?["hooks"] as? [[String: Any]])?.first)
  let command = try #require(handler["command"] as? String)
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/sh")
  p.arguments = ["-c", command]
  let out = Pipe()
  p.standardOutput = out
  try p.run()
  p.waitUntilExit()
  #expect(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "ok")
}
