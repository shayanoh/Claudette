import Foundation
import Testing

@testable import ClaudetteCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tool(_ name: String, id: String, input: String = "{}") -> ToolActivity {
  ToolActivity(
    toolUseID: id, toolName: name, mcpServer: nil,
    input: try? JSONDecoder().decode(JSONValue.self, from: Data(input.utf8)), startedAt: t0,
    isBackground: false)
}

private func read(_ path: String, id: String = UUID().uuidString) -> ToolActivity {
  tool("Read", id: id, input: #"{"file_path":"\#(path)"}"#)
}

@discardableResult
private func touch(
  _ w: inout WorldModel, _ session: String, _ t: ToolActivity, cwd: String? = "/proj",
  at: TimeInterval = 0
) -> (item: Item, isNew: Bool, evicted: [ItemID])? {
  w.touch(
    for: session, tool: t, scene: SceneMapper.scene(for: t, now: t0), cwd: cwd,
    now: t0.addingTimeInterval(at))
}

@Test func sameFileFromTwoSessionsIsOneItem() throws {
  var w = WorldModel()
  let a = try #require(touch(&w, "s1", read("/proj/a.swift")))
  let b = try #require(touch(&w, "s2", read("/proj/a.swift")))
  #expect(a.isNew && !b.isNew)
  #expect(a.item.id == b.item.id)
  #expect(w.all.count == 1)
  #expect(w.all[0].owners == ["s1", "s2"])
}

@Test func sameBasenameInDifferentFoldersAreTwoItems() throws {
  var w = WorldModel()
  touch(&w, "s1", read("/proj/a/index.ts"))
  touch(&w, "s1", read("/proj/b/index.ts"))
  #expect(w.all.count == 2)
  #expect(Set(w.all.map(\.label)) == ["index.ts"])
}

@Test func relativePathResolvesAgainstCwd() throws {
  var w = WorldModel()
  let rel = try #require(touch(&w, "s1", read("src/a.swift"), cwd: "/proj"))
  let abs = try #require(touch(&w, "s1", read("/proj/src/a.swift")))
  #expect(rel.item.id == abs.item.id)
}

@Test func relativePathWithoutCwdFallsBackToAToolItem() throws {
  var w = WorldModel()
  let a = try #require(touch(&w, "s1", read("a.swift", id: "r1"), cwd: nil))
  let b = try #require(touch(&w, "s1", read("a.swift", id: "r2"), cwd: nil))
  #expect(a.item.id != b.item.id)
}

@Test func dotDotAndTrailingSlashNormalise() {
  let a = ItemID.file(path: "/proj/x/../a.swift", cwd: nil)
  let b = ItemID.file(path: "/proj/a.swift/", cwd: nil)
  #expect(a != nil && a == b)
}

@Test func symlinkResolvesToTarget() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let real = dir.appendingPathComponent("real.txt")
  try Data("x".utf8).write(to: real)
  let link = dir.appendingPathComponent("link.txt")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
  #expect(ItemID.file(path: link.path, cwd: nil) == ItemID.file(path: real.path, cwd: nil))
}

@Test func readEditWriteOnSamePathShareItem() throws {
  var w = WorldModel()
  touch(&w, "s1", read("/proj/a.swift"))
  touch(&w, "s1", tool("Edit", id: "e", input: #"{"file_path":"/proj/a.swift"}"#))
  touch(&w, "s1", tool("Write", id: "w", input: #"{"file_path":"/proj/a.swift"}"#))
  #expect(w.all.count == 1)
}

@Test func terminalsAreOneItemPerToolUseID() throws {
  var w = WorldModel()
  let a = try #require(touch(&w, "s1", tool("Bash", id: "b1", input: #"{"command":"ls -la"}"#)))
  let b = try #require(touch(&w, "s1", tool("Bash", id: "b2", input: #"{"command":"ls -la"}"#)))
  #expect(a.item.id != b.item.id)
  #expect(a.item.kind == .terminal)
  #expect(a.item.terminal?.command == "ls -la")
  #expect(a.item.terminal?.state == .running)
}

@Test func skillIsItsName() throws {
  var w = WorldModel()
  let a = try #require(touch(&w, "s1", tool("Skill", id: "k1", input: #"{"skill":"x:y"}"#)))
  let b = try #require(touch(&w, "s2", tool("Skill", id: "k2", input: #"{"skill":"x:y"}"#)))
  #expect(a.item.id == b.item.id)
}

@Test func subagentSpawnMakesNoItem() {
  var w = WorldModel()
  #expect(touch(&w, "s1", tool("Agent", id: "a1")) == nil)
  #expect(w.all.isEmpty)
}

@Test func touchRefreshesLastTouchedAndOwners() throws {
  var w = WorldModel()
  touch(&w, "s1", read("/proj/a"), at: 0)
  let again = try #require(touch(&w, "s2", read("/proj/a"), at: 50))
  #expect(again.item.lastTouched == t0.addingTimeInterval(50))
  #expect(again.item.createdAt == t0)
}

@Test func finishSetsTerminalStateAndResult() throws {
  var w = WorldModel()
  touch(&w, "s1", tool("Bash", id: "b1", input: #"{"command":"ls"}"#))
  let r = ToolResult(success: false, durationMs: 5, summary: "Exit code 1")
  w.finish(toolUseID: "b1", result: r)
  let item = try #require(w.all.first)
  #expect(item.terminal?.state == .failed)
  #expect(item.terminal?.result == r)
  w.finish(toolUseID: "unknown", result: r)  // ignored
}

@Test func releaseSessionKeepsSharedItemsAndReportsOnlyOwnerless() {
  var w = WorldModel()
  touch(&w, "s1", read("/proj/shared"))
  touch(&w, "s2", read("/proj/shared"))
  touch(&w, "s1", read("/proj/mine"))
  let ownerless = w.releaseSession("s1")
  #expect(ownerless.count == 1)
  #expect(w.all.count == 2)  // nothing is deleted until remove()
  #expect(w.items(ownedBy: "s1").isEmpty)
  #expect(w.items(ownedBy: "s2").count == 1)
  w.remove(ownerless)
  #expect(w.all.count == 1)
}

@Test func capEvictsOldestRestingItemsButNeverRunningTerminals() throws {
  var w = WorldModel()
  w.hardCap = 3
  touch(&w, "s1", tool("Bash", id: "b1", input: #"{"command":"sleep 99"}"#), at: 0)  // oldest, running
  touch(&w, "s1", read("/proj/a"), at: 1)
  touch(&w, "s1", read("/proj/b"), at: 2)
  let new = try #require(touch(&w, "s1", read("/proj/c"), at: 3))
  #expect(new.evicted.count == 1)
  #expect(w.all.count == 3)
  #expect(w.all.contains { $0.kind == .terminal })  // the running terminal survived
  #expect(!w.all.contains { $0.label == "a" })
}

@Test func moveRecordsPositionAndDisplay() throws {
  var w = WorldModel()
  let a = try #require(touch(&w, "s1", read("/proj/a")))
  w.move(a.item.id, to: CGPoint(x: 10, y: 20), display: 7)
  #expect(w.all[0].position == CGPoint(x: 10, y: 20))
  #expect(w.all[0].display == 7)
}
