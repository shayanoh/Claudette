import Foundation
import Testing

@testable import ClaudetteCore

private struct Env {
  let dir: URL
  var settings: URL { dir.appendingPathComponent("home/settings.json") }
  var project: URL { dir.appendingPathComponent("proj/settings.json") }
  var state: URL { dir.appendingPathComponent("state") }
  var wrapper: String { state.appendingPathComponent("claudette-statusline.sh").path }

  init() {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "claudette-sl-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(
      at: dir.appendingPathComponent("home"), withIntermediateDirectories: true)
  }
  func cleanup() { try? FileManager.default.removeItem(at: dir) }
  func write(_ text: String, to url: URL? = nil) {
    let u = url ?? settings
    try! FileManager.default.createDirectory(
      at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(text.utf8).write(to: u)
  }
  func read(_ url: URL? = nil) -> Data { try! Data(contentsOf: url ?? settings) }
  func json(_ url: URL? = nil) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: read(url)) as! [String: Any]
  }
  func install() throws -> InstallOutcome {
    try StatusLineInstaller.install(
      settingsURL: settings, wrapperPath: wrapper, stateDir: state, port: 47631)
  }
  func uninstall() throws -> UninstallOutcome {
    try StatusLineInstaller.uninstall(settingsURL: settings, wrapperPath: wrapper, stateDir: state)
  }
}

private func command(_ json: [String: Any]) -> String? {
  (json["statusLine"] as? [String: Any])?["command"] as? String
}

@Test func installOnMissingSettingsCreatesFileWithWrapper() throws {
  let e = Env()
  defer { e.cleanup() }
  #expect(try e.install() == .installed)
  let sl = try #require(e.json()["statusLine"] as? [String: Any])
  #expect(sl["type"] as? String == "command")
  #expect(command(e.json())?.contains("claudette-statusline.sh") == true)
  #expect(FileManager.default.isExecutableFile(atPath: e.wrapper))
}

@Test func installPreservesOtherKeys() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(#"{"model":"opus","permissions":{"allow":["Bash(ls)"]},"env":{"A":"1"}}"#)
  _ = try e.install()
  let j = e.json()
  #expect(j["model"] as? String == "opus")
  #expect((j["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls)"])
  #expect((j["env"] as? [String: Any])?["A"] as? String == "1")
}

@Test func installStoresAndWrapsExistingCommand() throws {
  let e = Env()
  defer { e.cleanup() }
  let original = #"bash -c "echo \"a b\"" --x"#
  let obj: [String: Any] = ["statusLine": ["type": "command", "command": original, "padding": 2]]
  e.write(String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self))
  _ = try e.install()
  let stored = try JSONSerialization.jsonObject(
    with: Data(contentsOf: e.state.appendingPathComponent("original-statusline.json")))
  #expect((stored as? [String: Any])?["command"] as? String == original)
  // padding is kept on the wrapped entry
  #expect((e.json()["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
}

@Test func installRefusesInvalidJSONAndLeavesFileUntouched() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write("{ this is not json")
  #expect(throws: InstallError.settingsNotValidJSON) { _ = try e.install() }
  #expect(String(decoding: e.read(), as: UTF8.self) == "{ this is not json")
  #expect(!FileManager.default.fileExists(atPath: e.wrapper))
}

@Test func installRefusesNonObjectJSON() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write("[1,2,3]")
  #expect(throws: InstallError.settingsNotValidJSON) { _ = try e.install() }
  #expect(String(decoding: e.read(), as: UTF8.self) == "[1,2,3]")
}

@Test func installIsIdempotent() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(#"{"statusLine":{"type":"command","command":"echo hi"}}"#)
  #expect(try e.install() == .installed)
  let after1 = e.read()
  #expect(try e.install() == .alreadyInstalled)
  #expect(e.read() == after1)
  let stored = try String(
    contentsOf: e.state.appendingPathComponent("original-statusline.json"), encoding: .utf8)
  #expect(stored.contains("echo hi"))  // the original, not our wrapper
}

@Test func uninstallRestoresOriginalBytes() throws {
  let e = Env()
  defer { e.cleanup() }
  let original =
    "{\n  \"model\": \"opus\",\n   \"statusLine\": {\"type\":\"command\",\"command\":\"echo hi\"}\n}\n"
  e.write(original)
  _ = try e.install()
  #expect(try e.uninstall() == .restored)
  #expect(String(decoding: e.read(), as: UTF8.self) == original)
}

@Test func uninstallDeletesFileWeCreated() throws {
  let e = Env()
  defer { e.cleanup() }
  _ = try e.install()
  #expect(try e.uninstall() == .restored)
  #expect(!FileManager.default.fileExists(atPath: e.settings.path))
}

@Test func uninstallAfterUserEditsRestoresOnlyTheStatusLine() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(#"{"statusLine":{"type":"command","command":"echo hi"}}"#)
  _ = try e.install()
  var j = e.json()
  j["theme"] = "dark"  // user edited settings after install
  try JSONSerialization.data(withJSONObject: j).write(to: e.settings)
  #expect(try e.uninstall() == .restored)
  let after = e.json()
  #expect(after["theme"] as? String == "dark")
  #expect(command(after) == "echo hi")
}

@Test func uninstallLeavesChangedStatusLineAlone() throws {
  let e = Env()
  defer { e.cleanup() }
  _ = try e.install()
  e.write(#"{"statusLine":{"type":"command","command":"my-own-thing"}}"#)
  #expect(try e.uninstall() == .leftAlone)
  #expect(command(e.json()) == "my-own-thing")
}

@Test func uninstallRemovesKeyWhenThereWasNoneButUserAddedOtherSettings() throws {
  let e = Env()
  defer { e.cleanup() }
  _ = try e.install()
  var j = e.json()
  j["model"] = "opus"
  try JSONSerialization.data(withJSONObject: j).write(to: e.settings)
  #expect(try e.uninstall() == .restored)
  #expect(e.json()["statusLine"] == nil)
  #expect(e.json()["model"] as? String == "opus")
}

@Test func uninstallWhenNeverInstalledIsANoOp() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(#"{"model":"opus"}"#)
  #expect(try e.uninstall() == .notInstalled)
  #expect(String(decoding: e.read(), as: UTF8.self) == #"{"model":"opus"}"#)
}

@Test func statusReportsInstalledAndOverriddenByProject() throws {
  let e = Env()
  defer { e.cleanup() }
  #expect(
    StatusLineInstaller.status(
      settingsURL: e.settings, wrapperPath: e.wrapper, projectSettingsURL: nil)
      == .notInstalled)
  _ = try e.install()
  #expect(
    StatusLineInstaller.status(
      settingsURL: e.settings, wrapperPath: e.wrapper, projectSettingsURL: e.project)
      == .installed)
  e.write(#"{"statusLine":{"type":"command","command":"project-line"}}"#, to: e.project)
  #expect(
    StatusLineInstaller.status(
      settingsURL: e.settings, wrapperPath: e.wrapper, projectSettingsURL: e.project)
      == .overriddenByProject)
}

@Test func uninstallKeepsBackupWhenSettingsAreUnreadable() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(#"{"statusLine":{"type":"command","command":"echo hi"}}"#)
  _ = try e.install()
  let good = e.read()
  e.write(#"{"statusLine": {"command": "x""#)  // the user broke the file (truncated)
  #expect(throws: InstallError.settingsNotValidJSON) { _ = try e.uninstall() }
  // Nothing may be deleted on failure: the original status line must still be recoverable.
  #expect(FileManager.default.fileExists(atPath: e.wrapper))
  #expect(
    FileManager.default.fileExists(
      atPath: e.state.appendingPathComponent("original-statusline.json").path))
  #expect(
    FileManager.default.fileExists(atPath: e.state.appendingPathComponent("settings.backup").path))
  try good.write(to: e.settings)  // the user fixes the file
  #expect(try e.uninstall() == .restored)
  #expect(command(e.json()) == "echo hi")
}

@Test func symlinkedSettingsStaysASymlink() throws {
  let e = Env()
  defer { e.cleanup() }
  let target = e.dir.appendingPathComponent("dotfiles/settings.json")
  e.write(#"{"model":"opus"}"#, to: target)
  try FileManager.default.createSymbolicLink(at: e.settings, withDestinationURL: target)
  _ = try e.install()
  let attrs = try FileManager.default.attributesOfItem(atPath: e.settings.path)
  #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
  #expect(command(e.json(target)) != nil)  // the real file got the change
  #expect(try e.uninstall() == .restored)
  let after = try FileManager.default.attributesOfItem(atPath: e.settings.path)
  #expect(after[.type] as? FileAttributeType == .typeSymbolicLink)
  #expect(String(decoding: e.read(target), as: UTF8.self) == #"{"model":"opus"}"#)
}

@Test func installRepairsAMissingWrapperScript() throws {
  let e = Env()
  defer { e.cleanup() }
  _ = try e.install()
  try FileManager.default.removeItem(atPath: e.wrapper)
  #expect(try e.install() == .installed)  // not "already installed" while the script is gone
  #expect(FileManager.default.isExecutableFile(atPath: e.wrapper))
}

// MARK: - The wrapper script itself

private func runWrapper(_ e: Env, input: String) throws -> (out: String, code: Int32) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/bash")
  p.arguments = [e.wrapper]
  let stdin = Pipe()
  let stdout = Pipe()
  p.standardInput = stdin
  p.standardOutput = stdout
  try p.run()
  stdin.fileHandleForWriting.write(Data(input.utf8))
  try stdin.fileHandleForWriting.close()
  let data = stdout.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  return (String(decoding: data, as: UTF8.self), p.terminationStatus)
}

@Test func wrapperWithNoOriginalPrintsEmptyLineAndExits0EvenWhenAppIsDown() throws {
  let e = Env()
  defer { e.cleanup() }
  _ = try StatusLineInstaller.install(
    settingsURL: e.settings, wrapperPath: e.wrapper, stateDir: e.state, port: 1)  // nothing listens
  let r = try runWrapper(e, input: #"{"session_id":"s1"}"#)
  #expect(r.out == "\n")
  #expect(r.code == 0)
}

@Test func wrapperPipesInputThroughOriginalCommand() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(#"{"statusLine":{"type":"command","command":"cat"}}"#)
  _ = try StatusLineInstaller.install(
    settingsURL: e.settings, wrapperPath: e.wrapper, stateDir: e.state, port: 1)
  let input = #"{"session_id":"s1","note":"a b \"q\""}"#
  let r = try runWrapper(e, input: input)
  #expect(r.out == input)
  #expect(r.code == 0)
}

@Test func wrapperKeepsQuotedMultiArgOriginalCommandIntact() throws {
  let e = Env()
  defer { e.cleanup() }
  e.write(
    #"{"statusLine":{"type":"command","command":"printf '%s|' \"two words\" x; cat >/dev/null"}}"#)
  _ = try StatusLineInstaller.install(
    settingsURL: e.settings, wrapperPath: e.wrapper, stateDir: e.state, port: 1)
  let r = try runWrapper(e, input: "{}")
  #expect(r.out == "two words|x|")
}

@Test func wrapperForwardsPayloadToFeedServer() async throws {
  final class Box: @unchecked Sendable {
    let lock = NSLock()
    var got: [FeedMessage] = []
  }
  let box = Box()
  let server = FeedServer(port: 0) {
    box.lock.lock()
    box.got.append($0)
    box.lock.unlock()
  }
  try server.start()
  defer { server.stop() }
  let e = Env()
  defer { e.cleanup() }
  _ = try StatusLineInstaller.install(
    settingsURL: e.settings, wrapperPath: e.wrapper, stateDir: e.state,
    port: Int(try #require(server.boundPort)))
  let payload =
    #"{"session_id":"s9","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1738425600}}}"#
  _ = try runWrapper(e, input: payload)
  for _ in 0..<40 {  // curl runs in the background
    box.lock.lock()
    let n = box.got.count
    box.lock.unlock()
    if n > 0 { break }
    try await Task.sleep(nanoseconds: 100_000_000)
  }
  box.lock.lock()
  defer { box.lock.unlock() }
  guard case .status(let d)? = box.got.first else {
    Issue.record("wrapper did not deliver a status message")
    return
  }
  #expect(try StatusPayload.decode(d).sessionID == "s9")
}
