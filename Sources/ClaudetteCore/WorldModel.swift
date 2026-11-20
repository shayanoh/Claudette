import CoreGraphics
import Foundation

public enum ItemKind: Equatable, Sendable {
  case file, terminal
  case tool(ToolScene)
}

/// Identity of something lying on the screen. Files are their absolute normalised path (so the same
/// file is one item for every session and sub-agent); skills are their name; every other tool call
/// is its `tool_use_id`.
public struct ItemID: Hashable, Sendable {
  public let raw: String

  init(raw: String) { self.raw = raw }

  /// nil for an empty path, or a relative path with no usable `cwd`.
  public static func file(path: String, cwd: String?) -> ItemID? {
    guard !path.isEmpty else { return nil }
    let url: URL
    if path.hasPrefix("/") {
      url = URL(fileURLWithPath: path)
    } else {
      guard let cwd, cwd.hasPrefix("/") else { return nil }
      url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
    }
    return ItemID(raw: "file:" + url.standardizedFileURL.resolvingSymlinksInPath().path)
  }

  public static func tool(useID: String) -> ItemID { ItemID(raw: "tool:" + useID) }
  public static func skill(name: String) -> ItemID { ItemID(raw: "skill:" + name) }
}

public enum TerminalState: Equatable, Sendable { case running, done, failed }

public struct TerminalInfo: Equatable, Sendable {
  public var command: String
  public var state: TerminalState
  public var result: ToolResult?
}

public struct Item: Equatable, Sendable {
  public let id: ItemID
  public let kind: ItemKind
  public var label: String
  public var owners: Set<String>
  public let createdAt: Date
  public var lastTouched: Date
  public var position: CGPoint?
  public var display: UInt32?
  public var terminal: TerminalInfo?
}

/// Everything lying around on screen, shared by all sessions. Pure data: no UI.
public struct WorldModel {
  /// Hard cap on items; beyond it the oldest resting items are evicted.
  public var hardCap = 80
  private var store: [ItemID: Item] = [:]

  public init() {}

  public var all: [Item] {
    store.values.sorted { ($0.createdAt, $0.id.raw) < ($1.createdAt, $1.id.raw) }
  }

  public func item(_ id: ItemID) -> Item? { store[id] }

  public func items(ownedBy session: String) -> [Item] {
    all.filter { $0.owners.contains(session) }
  }

  private struct Spec {
    var id: ItemID
    var kind: ItemKind
    var label: String
    var terminal: TerminalInfo?
  }

  /// nil for a sub-agent spawn (it is an actor, not an item).
  private static func spec(tool: ToolActivity, scene: ToolScene, cwd: String?) -> Spec? {
    let byUse = ItemID.tool(useID: tool.toolUseID)
    func path() -> String? {
      tool.input?["file_path"]?.stringValue ?? tool.input?["notebook_path"]?.stringValue
    }
    func fileSpec(_ name: String) -> Spec {
      if let p = path(), let id = ItemID.file(path: p, cwd: cwd) {
        let base = (p as NSString).lastPathComponent
        return Spec(id: id, kind: .file, label: base.isEmpty ? name : base)
      }
      return Spec(id: byUse, kind: .tool(scene), label: name)
    }
    switch scene {
    case .subagent: return nil
    case .read(let f): return fileSpec(f)
    case .edit(let f), .write(let f): return fileSpec(f ?? "")
    case .shell:
      let command = tool.input?["command"]?.stringValue ?? ""
      let first = command.split(separator: "\n", omittingEmptySubsequences: true).first
      return Spec(
        id: byUse, kind: .terminal, label: first.map(String.init) ?? "shell",
        terminal: TerminalInfo(command: command, state: .running, result: nil))
    case .skill(let name):
      let id = name.isEmpty ? byUse : ItemID.skill(name: name)
      return Spec(id: id, kind: .tool(scene), label: name.isEmpty ? "skill" : name)
    case .mcp(let server, _): return Spec(id: byUse, kind: .tool(scene), label: server)
    case .search: return Spec(id: byUse, kind: .tool(scene), label: "search")
    case .web: return Spec(id: byUse, kind: .tool(scene), label: "web")
    case .todo: return Spec(id: byUse, kind: .tool(scene), label: "todo")
    case .plan: return Spec(id: byUse, kind: .tool(scene), label: "plan")
    case .other(let name): return Spec(id: byUse, kind: .tool(scene), label: name)
    }
  }

  /// Records that `session` used something: reuses the item already on screen for the same
  /// identity, otherwise makes a new one (unplaced: the caller scatters it near the actor).
  @discardableResult
  public mutating func touch(
    for session: String, tool: ToolActivity, scene: ToolScene, cwd: String?, now: Date
  ) -> (item: Item, isNew: Bool, evicted: [ItemID])? {
    guard let spec = Self.spec(tool: tool, scene: scene, cwd: cwd) else { return nil }
    let isNew: Bool
    if var existing = store[spec.id] {
      existing.owners.insert(session)
      existing.lastTouched = now
      store[spec.id] = existing
      isNew = false
    } else {
      store[spec.id] = Item(
        id: spec.id, kind: spec.kind, label: spec.label, owners: [session], createdAt: now,
        lastTouched: now, position: nil, display: nil, terminal: spec.terminal)
      isNew = true
    }
    let evicted = evict(keeping: spec.id)
    return (store[spec.id]!, isNew, evicted)
  }

  private mutating func evict(keeping keep: ItemID) -> [ItemID] {
    var evicted: [ItemID] = []
    let cap = max(1, hardCap)
    while store.count > cap {
      let victim =
        store.values
        .filter { $0.id != keep && $0.terminal?.state != .running }
        .min { ($0.lastTouched, $0.id.raw) < ($1.lastTouched, $1.id.raw) }
      guard let victim else { break }
      store[victim.id] = nil
      evicted.append(victim.id)
    }
    return evicted
  }

  public mutating func finish(toolUseID: String, result: ToolResult) {
    let id = ItemID.tool(useID: toolUseID)
    guard var item = store[id], item.terminal != nil else { return }
    item.terminal?.state = result.success ? .done : .failed
    item.terminal?.result = result
    store[id] = item
  }

  public mutating func move(_ id: ItemID, to point: CGPoint, display: UInt32) {
    guard store[id] != nil, point.x.isFinite, point.y.isFinite else { return }
    store[id]!.position = point
    store[id]!.display = display
  }

  /// Removes `session` from every item's owners and returns the items that now have no owner.
  /// They stay in the model until `remove` (the leaving actor collects them first).
  public mutating func releaseSession(_ session: String) -> [ItemID] {
    var ownerless: [ItemID] = []
    for id in store.keys.sorted(by: { $0.raw < $1.raw }) {
      guard store[id]!.owners.remove(session) != nil else { continue }
      if store[id]!.owners.isEmpty { ownerless.append(id) }
    }
    return ownerless
  }

  public mutating func remove(_ ids: [ItemID]) {
    for id in ids { store[id] = nil }
  }
}
