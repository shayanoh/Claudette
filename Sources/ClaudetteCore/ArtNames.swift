import Foundation

/// Maps app state to art asset names (see the manifest contract in `ArtManifest`).
public enum ArtNames {
  public static let bangBubble = "status_bang"
  public static let questionBubble = "status_question"
  public static let mcpCable = "prop_mcp_cable"
  static let knownServers: Set<String> = ["github", "playwright", "figma", "context7"]

  /// The prop asset for a tool scene; `nil` for sub-agents (the mini is the visual).
  public static func prop(for scene: ToolScene) -> String? {
    switch scene {
    case .read: return "prop_read"
    case .search: return "prop_search"
    case .edit: return "prop_edit"
    case .write: return "prop_write"
    case .shell(let long, let background):
      return background ? "prop_shell_bg" : (long ? "prop_shell_long" : "prop_shell")
    case .web: return "prop_web"
    case .skill: return "prop_skill"
    case .mcp(let server, _): return "prop_mcp_" + (knownServer(server) ?? "generic")
    case .todo: return "prop_todo"
    case .plan: return "prop_plan"
    case .subagent: return nil
    case .other: return "prop_other"
    }
  }

  /// First token of the server name that is a known server, e.g. `plugin_github_github`.
  public static func knownServer(_ server: String) -> String? {
    server.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map(String.init).first(where: knownServers.contains)
  }

  public static func errorPill(_ kind: ErrorKind) -> String {
    switch kind {
    case .api: return "status_err_api"
    case .auth: return "status_err_auth"
    case .billing: return "status_err_billing"
    case .rateLimit: return "status_err_ratelimit"
    case .disconnect: return "status_err_offline"
    case .unknown: return "status_err_unknown"
    }
  }
}

public enum StableHash {
  /// FNV-1a, 64 bit. Unlike `hashValue` it is the same in every process.
  public static func fnv1a64(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
      h ^= UInt64(b)
      h = h &* 0x0000_0100_0000_01b3
    }
    return h
  }
}

public enum Accent {
  /// Hue in 0..<1 for a project path; empty or blank paths count as "/".
  public static func hue(forProject path: String) -> Double {
    let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return Double(StableHash.fnv1a64(p.isEmpty ? "/" : p) % 360) / 360
  }
}

public enum ModelFamily: Equatable, Sendable {
  case opus, sonnet, haiku, other

  public static func from(displayName: String?) -> ModelFamily {
    let n = (displayName ?? "").lowercased()
    if n.contains("opus") { return .opus }
    if n.contains("sonnet") { return .sonnet }
    if n.contains("haiku") { return .haiku }
    return .other
  }
}

public enum SleepDepth: Equatable, Sendable {
  case awake, nap, deep

  /// Weekly limit beats the 5-hour one.
  public static func from(five: LimitStatus, seven: LimitStatus) -> SleepDepth {
    seven == .inLimit ? .deep : (five == .inLimit ? .nap : .awake)
  }
}
