import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tool(_ name: String, id: String = "t1", input: String = "{}", bg: Bool = false)
  -> ToolActivity
{
  ToolActivity(
    toolUseID: id, toolName: name,
    input: try? JSONDecoder().decode(JSONValue.self, from: Data(input.utf8)), startedAt: t0,
    isBackground: bg)
}

private func touched(_ t: ToolActivity, cwd: String? = "/Users/me/proj/Claudette") -> Item {
  var w = WorldModel()
  return w.touch(
    for: "sess-12345678", tool: t, scene: SceneMapper.scene(for: t, now: t0), cwd: cwd, now: t0)!
    .item
}

@Test func anItemRemembersWhereAndWhatItCameFrom() {
  let i = touched(
    tool("Bash", input: #"{"command":"ls","description":"List files","timeout":30000}"#))
  #expect(i.cwd == "/Users/me/proj/Claudette")
  #expect(i.toolName == "Bash")
  #expect(i.facts.contains(ItemFact(label: "Command", value: "ls")))
  #expect(i.facts.contains(ItemFact(label: "Description", value: "List files")))
  #expect(i.facts.contains(ItemFact(label: "Timeout", value: "30 s")))
}

@Test func toolFactsCoverSearchWebSkillAndMCP() {
  let grep = touched(tool("Grep", input: #"{"pattern":"foo.*bar","path":"/src"}"#))
  #expect(grep.facts.map(\.label) == ["Pattern", "Path"])
  let web = touched(
    tool("WebFetch", input: #"{"url":"https://example.com/x","prompt":"summarise"}"#))
  #expect(web.facts.first == ItemFact(label: "URL", value: "https://example.com/x"))
  let skill = touched(tool("Skill", input: #"{"skill":"superpowers:brainstorming"}"#))
  #expect(skill.facts == [ItemFact(label: "Skill", value: "superpowers:brainstorming")])
  let mcp = ToolActivity(
    toolUseID: "m1", toolName: "mcp__github__create_issue", mcpServer: "github", input: nil,
    startedAt: t0)
  let m = touched(mcp)
  #expect(m.facts.contains(ItemFact(label: "Server", value: "github")))
  #expect(m.facts.contains(ItemFact(label: "Tool", value: "create_issue")))
}

@Test func hugeFactValuesAreCapped() {
  let big = String(repeating: "x", count: 5000)
  let i = touched(tool("Bash", input: #"{"command":"\#(big)"}"#))
  #expect((i.facts.first { $0.label == "Command" }?.value.count ?? 0) <= 2001)
}

@Test func aLongCommandHoversAsAFewWrappedLinesWithAnEllipsis() {
  let command = (1...80).map { "arg\($0)" }.joined(separator: " ")
  let i = touched(tool("Bash", input: #"{"command":"\#(command)"}"#))
  let lines = ItemDetails.hover(i)
  let commandLines = lines.dropLast()  // the last line is the status
  #expect(commandLines.count == 4)
  #expect(commandLines.last?.hasSuffix("…") == true)
  #expect(lines.last == "running…")
}

@Test func aShortCommandHoversWhole() {
  let i = touched(tool("Bash", input: #"{"command":"swift test"}"#))
  #expect(ItemDetails.hover(i) == ["swift test", "running…"])
}

@Test func aFinishedTerminalHoverShowsStatusDurationAndTheLastResultLine() {
  var w = WorldModel()
  let t = tool("Bash", input: #"{"command":"make"}"#)
  _ = w.touch(for: "s", tool: t, scene: SceneMapper.scene(for: t, now: t0), cwd: nil, now: t0)
  w.finish(
    toolUseID: "t1",
    result: ToolResult(success: true, durationMs: 15286, summary: "building\nBuild complete!"))
  let lines = ItemDetails.hover(w.all[0])
  #expect(lines == ["make", "done · 15.3 s", "Build complete!"])
}

@Test func aFileHoversAsItsPathAndOtherToolsAsASummary() {
  let f = touched(tool("Read", input: #"{"file_path":"/Users/me/proj/a.swift"}"#))
  #expect(ItemDetails.hover(f) == ["/Users/me/proj/a.swift"])
  let g = touched(tool("Grep", input: #"{"pattern":"foo","path":"/src"}"#))
  #expect(ItemDetails.hover(g) == ["Pattern: foo · Path: /src"])
  let todo = touched(tool("TodoWrite"))
  #expect(ItemDetails.hover(todo) == ["todo"])
}

@Test func theDetailWindowListsEverythingWeKnow() {
  var w = WorldModel()
  let t = tool("Bash", input: #"{"command":"make","description":"Build"}"#)
  _ = w.touch(
    for: "sess-12345678", tool: t, scene: SceneMapper.scene(for: t, now: t0),
    cwd: "/Users/me/proj/Claudette", now: t0)
  w.finish(
    toolUseID: "t1", result: ToolResult(success: false, durationMs: 200, summary: "Exit code 2"))
  let rows = ItemDetails.rows(w.all[0])
  func value(_ label: String) -> String? { rows.first { $0.label == label }?.value }
  #expect(value("Kind") == "Terminal")
  #expect(value("Command") == "make")
  #expect(value("Status") == "Failed")
  #expect(value("Duration") == "0.2 s")
  #expect(value("Result (last 200 characters)") == "Exit code 2")
  #expect(value("Project") == "Claudette")
  #expect(value("Folder") == "/Users/me/proj/Claudette")
  #expect(value("Session") == "sess-123")
  #expect(rows.first { $0.label == "Command" }?.mono == true)
}

@Test func sharedItemsListEverySessionAndMissingDataIsSkipped() {
  var w = WorldModel()
  let t = tool("Read", input: #"{"file_path":"/a/b.swift"}"#)
  let scene = SceneMapper.scene(for: t, now: t0)
  _ = w.touch(for: "aaaaaaaa1", tool: t, scene: scene, cwd: nil, now: t0)
  _ = w.touch(for: "bbbbbbbb2", tool: t, scene: scene, cwd: nil, now: t0)
  let rows = ItemDetails.rows(w.all[0])
  #expect(rows.first { $0.label == "Session" }?.value == "aaaaaaaa, bbbbbbbb")
  #expect(!rows.contains { $0.label == "Project" })
}
