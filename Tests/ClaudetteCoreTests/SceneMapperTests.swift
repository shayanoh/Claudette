import Foundation
import Testing

@testable import ClaudetteCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tool(
  _ name: String, input: String = "{}", server: String? = nil, background: Bool = false,
  started: Date = t0
) -> ToolActivity {
  ToolActivity(
    toolUseID: "t", toolName: name, mcpServer: server,
    input: try? JSONDecoder().decode(JSONValue.self, from: Data(input.utf8)),
    startedAt: started, isBackground: background)
}

@Test func readFileShowsBasename() {
  #expect(
    SceneMapper.scene(for: tool("Read", input: #"{"file_path":"/a/b/auth.ts"}"#), now: t0)
      == .read(file: "auth.ts"))
}

@Test func grepGlobAreSearch() {
  #expect(SceneMapper.scene(for: tool("Grep"), now: t0) == .search)
  #expect(SceneMapper.scene(for: tool("Glob"), now: t0) == .search)
}

@Test func editWriteMultiEditAndNotebook() {
  #expect(
    SceneMapper.scene(for: tool("Edit", input: #"{"file_path":"/x/y.swift"}"#), now: t0)
      == .edit(file: "y.swift"))
  #expect(SceneMapper.scene(for: tool("MultiEdit"), now: t0) == .edit(file: nil))
  #expect(
    SceneMapper.scene(for: tool("Write", input: #"{"file_path":"/x/new.md"}"#), now: t0)
      == .write(file: "new.md"))
  #expect(SceneMapper.scene(for: tool("NotebookEdit"), now: t0) == .edit(file: nil))
}

@Test func bashBecomesLongAfter10s() {
  #expect(
    SceneMapper.scene(for: tool("Bash"), now: t0.addingTimeInterval(9))
      == .shell(long: false, background: false))
  #expect(
    SceneMapper.scene(for: tool("Bash"), now: t0.addingTimeInterval(10))
      == .shell(long: true, background: false))
  #expect(
    SceneMapper.scene(for: tool("Bash", background: true), now: t0.addingTimeInterval(99))
      == .shell(long: false, background: true))
}

@Test func mcpToolSplitsServerAndTool() {
  #expect(
    SceneMapper.scene(
      for: tool("mcp__plugin_figma_figma__get_design_context", server: "plugin_figma_figma"),
      now: t0) == .mcp(server: "plugin_figma_figma", tool: "get_design_context"))
  #expect(
    SceneMapper.scene(for: tool("mcp__context7__resolve-library-id", server: "context7"), now: t0)
      == .mcp(server: "context7", tool: "resolve-library-id"))
}

@Test func skillAgentWebTodoPlan() {
  #expect(
    SceneMapper.scene(for: tool("Skill", input: #"{"skill":"brainstorming"}"#), now: t0)
      == .skill(name: "brainstorming"))
  #expect(SceneMapper.scene(for: tool("Agent"), now: t0) == .subagent)
  #expect(SceneMapper.scene(for: tool("Task"), now: t0) == .subagent)
  #expect(SceneMapper.scene(for: tool("WebFetch"), now: t0) == .web)
  #expect(SceneMapper.scene(for: tool("WebSearch"), now: t0) == .web)
  #expect(SceneMapper.scene(for: tool("TodoWrite"), now: t0) == .todo)
  #expect(SceneMapper.scene(for: tool("ExitPlanMode"), now: t0) == .plan)
}

@Test func unknownToolIsOther() {
  #expect(SceneMapper.scene(for: tool("Brand_new"), now: t0) == .other(tool: "Brand_new"))
}

@Test func missingOrOddInputDoesNotCrash() {
  #expect(SceneMapper.scene(for: tool("Read", input: "null"), now: t0) == .read(file: ""))
  #expect(
    SceneMapper.scene(for: tool("Read", input: #"{"file_path":42}"#), now: t0) == .read(file: ""))
  #expect(SceneMapper.scene(for: tool("Skill", input: "{}"), now: t0) == .skill(name: ""))
}
