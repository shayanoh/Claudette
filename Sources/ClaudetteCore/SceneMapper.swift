import Foundation

/// What Claudette acts out for a tool call. (Named `ToolScene`: `Scene` clashes with SwiftUI.)
public enum ToolScene: Equatable, Sendable {
  case read(file: String)
  case search
  case edit(file: String?)
  case write(file: String?)
  case shell(long: Bool, background: Bool)
  case web
  case skill(name: String)
  case mcp(server: String, tool: String)
  case todo
  case plan
  case subagent
  case other(tool: String)
}

public enum SceneMapper {
  public static func scene(for tool: ToolActivity, now: Date) -> ToolScene {
    let name = tool.toolName
    if let server = tool.mcpServer {
      return .mcp(server: server, tool: mcpToolName(name, server: server))
    }
    switch name {
    case "Read": return .read(file: basename(tool.input?["file_path"]?.stringValue) ?? "")
    case "Grep", "Glob": return .search
    case "Edit", "MultiEdit", "NotebookEdit":
      return .edit(file: basename(tool.input?["file_path"]?.stringValue))
    case "Write": return .write(file: basename(tool.input?["file_path"]?.stringValue))
    case "Bash":
      let long =
        !tool.isBackground && now.timeIntervalSince(tool.startedAt) >= SessionStore.longShellAfter
      return .shell(long: long, background: tool.isBackground)
    case "WebFetch", "WebSearch": return .web
    case "Skill": return .skill(name: tool.input?["skill"]?.stringValue ?? "")
    case "Agent", "Task": return .subagent
    case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList": return .todo
    case "EnterPlanMode", "ExitPlanMode": return .plan
    default: return .other(tool: name)
    }
  }

  private static func basename(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    return (path as NSString).lastPathComponent
  }

  /// `mcp__<server>__<tool>` gives `<tool>`; falls back to the full name.
  private static func mcpToolName(_ full: String, server: String) -> String {
    let prefix = "mcp__\(server)__"
    return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
  }
}
