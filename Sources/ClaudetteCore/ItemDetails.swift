import Foundation

/// One labelled line of an item's detail window.
public struct DetailRow: Equatable, Sendable {
  public var label: String
  public var value: String
  /// Shown in a monospaced font (commands, paths, output).
  public var mono: Bool
}

/// What an item says about itself: a short hover summary and the full list for its detail window.
public enum ItemDetails {
  private static let monoLabels: Set<String> = [
    "Command", "File", "Path", "Folder", "URL", "Pattern", "Result (last 200 characters)",
  ]

  static func kindName(_ item: Item) -> String {
    switch item.kind {
    case .file: return "File"
    case .terminal: return "Terminal"
    case .tool(let scene):
      switch scene {
      case .search: return "Search"
      case .web: return "Web"
      case .skill: return "Skill"
      case .mcp: return "MCP tool"
      case .todo: return "To-do list"
      case .plan: return "Plan"
      case .other(let name): return "Tool: \(name)"
      case .read, .edit, .write, .shell, .subagent: return "Tool"
      }
    }
  }

  private static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

  /// Few short lines for the hover: a command wrapped to a few lines, a path, a tool's arguments.
  public static func hover(_ item: Item) -> [String] {
    switch item.kind {
    case .file:
      let path = item.facts.first { $0.label == "File" }?.value ?? item.label
      return TextWrap.wrap(path, wordsPerLine: 12, maxCharsPerLine: 80, maxLines: 3)
    case .terminal:
      guard let t = item.terminal else { return [item.label] }
      var lines = TextWrap.wrap(t.command, wordsPerLine: 12, maxCharsPerLine: 80, maxLines: 4)
      if lines.isEmpty { lines = [item.label] }
      switch t.state {
      case .running: lines.append("running…")
      case .done, .failed:
        lines.append(
          (t.state == .done ? "done" : "failed")
            + (t.result?.durationMs.map { " · " + seconds($0) } ?? ""))
        if let last = t.result?.summary?.split(separator: "\n").last {
          lines.append(String(last.trimmingCharacters(in: .whitespaces).prefix(80)))
        }
      }
      return lines
    case .tool:
      guard !item.facts.isEmpty else { return [item.label] }
      let text = item.facts.map { "\($0.label): \($0.value)" }.joined(separator: " · ")
      return TextWrap.wrap(text, wordsPerLine: 12, maxCharsPerLine: 80, maxLines: 3)
    }
  }

  /// Everything known about the item, for the window that opens on a click.
  public static func rows(_ item: Item) -> [DetailRow] {
    var out: [DetailRow] = []
    func add(_ label: String, _ value: String?) {
      guard let value, !value.isEmpty else { return }
      out.append(DetailRow(label: label, value: value, mono: monoLabels.contains(label)))
    }
    add("Kind", kindName(item))
    for f in item.facts { add(f.label, f.value) }
    if item.kind == .file, !item.facts.contains(where: { $0.label == "File" }) {
      add("File", String(item.id.raw.dropFirst("file:".count)))
    }
    if let t = item.terminal {
      add("Status", t.state == .running ? "Running" : (t.state == .done ? "Done" : "Failed"))
      add("Duration", t.result?.durationMs.map(seconds))
      add("Result (last 200 characters)", t.result?.summary)
    }
    if let cwd = item.cwd, !cwd.isEmpty {
      add("Project", (cwd as NSString).lastPathComponent)
      add("Folder", cwd)
    }
    add("Session", item.owners.sorted().map { String($0.prefix(8)) }.joined(separator: ", "))
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    add("First seen", f.string(from: item.createdAt))
    add("Last used", f.string(from: item.lastTouched))
    return out
  }
}
