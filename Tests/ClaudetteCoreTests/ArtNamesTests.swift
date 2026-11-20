import Foundation
import Testing

@testable import ClaudetteCore

@Test func fnvMatchesKnownVector() {
  #expect(StableHash.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
  #expect(StableHash.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
}

@Test func accentIsStableAndInRange() {
  let h = Accent.hue(forProject: "/Users/me/proj")
  #expect(h >= 0 && h < 1)
  #expect(h == Accent.hue(forProject: "/Users/me/proj"))
  #expect(Accent.hue(forProject: "") == Accent.hue(forProject: "/"))
  #expect(Accent.hue(forProject: "  ") == Accent.hue(forProject: "/"))
}

@Test func propNamesCoverEveryScene() {
  #expect(ArtNames.prop(for: .read(file: "a")) == "prop_read")
  #expect(ArtNames.prop(for: .search) == "prop_search")
  #expect(ArtNames.prop(for: .edit(file: nil)) == "prop_edit")
  #expect(ArtNames.prop(for: .write(file: "x")) == "prop_write")
  #expect(ArtNames.prop(for: .shell(long: false, background: false)) == "prop_shell")
  #expect(ArtNames.prop(for: .shell(long: true, background: false)) == "prop_shell_long")
  #expect(ArtNames.prop(for: .shell(long: false, background: true)) == "prop_shell_bg")
  #expect(ArtNames.prop(for: .web) == "prop_web")
  #expect(ArtNames.prop(for: .skill(name: "s")) == "prop_skill")
  #expect(ArtNames.prop(for: .todo) == "prop_todo")
  #expect(ArtNames.prop(for: .plan) == "prop_plan")
  #expect(ArtNames.prop(for: .subagent) == nil)
  #expect(ArtNames.prop(for: .other(tool: "X")) == "prop_other")
}

@Test func mcpKnownVsGeneric() {
  #expect(ArtNames.prop(for: .mcp(server: "plugin_github_github", tool: "t")) == "prop_mcp_github")
  #expect(ArtNames.prop(for: .mcp(server: "context7", tool: "t")) == "prop_mcp_context7")
  #expect(ArtNames.prop(for: .mcp(server: "Figma", tool: "t")) == "prop_mcp_figma")
  #expect(ArtNames.prop(for: .mcp(server: "claude-in-chrome", tool: "t")) == "prop_mcp_generic")
  #expect(ArtNames.prop(for: .mcp(server: "", tool: "t")) == "prop_mcp_generic")
  #expect(ArtNames.knownServer("plugin_playwright_playwright") == "playwright")
}

@Test func errorPillsDistinct() {
  let kinds: [ErrorKind] = [.api, .auth, .billing, .rateLimit, .disconnect, .unknown]
  #expect(Set(kinds.map(ArtNames.errorPill)).count == 6)
  #expect(ArtNames.errorPill(.rateLimit) == "status_err_ratelimit")
  #expect(ArtNames.errorPill(.disconnect) == "status_err_offline")
}

@Test func modelFamily() {
  #expect(ModelFamily.from(displayName: "Opus 4.7") == .opus)
  #expect(ModelFamily.from(displayName: "claude-sonnet-5-5") == .sonnet)
  #expect(ModelFamily.from(displayName: "Haiku") == .haiku)
  #expect(ModelFamily.from(displayName: nil) == .other)
  #expect(ModelFamily.from(displayName: "") == .other)
  #expect(ModelFamily.from(displayName: "Fable") == .other)
}

@Test func sleepDepthPrecedence() {
  let all: [LimitStatus] = [.unknown, .fresh, .low, .inLimit]
  for f in all {
    for s in all {
      let expected: SleepDepth = s == .inLimit ? .deep : (f == .inLimit ? .nap : .awake)
      #expect(SleepDepth.from(five: f, seven: s) == expected)
    }
  }
}
