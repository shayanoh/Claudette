import CoreGraphics
import Foundation

/// Seedable generator (SplitMix64) so planning is reproducible in tests.
public struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64
  public init(seed: UInt64) { state = seed }
  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// A named animation the app plays.
public enum Move: String, Sendable {
  case think, read, typing, search, shrug, celebrate, startled, yawn, stretch, trip
}

/// One thing for an actor to do. The brain plans a short queue; the app animates it and reports
/// back when it is finished or interrupted.
public enum Intent: Equatable, Sendable {
  case walk(to: CGPoint)
  case face(CGPoint)
  case play(Move)
  case pickUp(ItemID)
  case putDown(at: CGPoint)
  case toss(ItemID, to: CGPoint)
  case sit(onWindow: Int)
  case fall
  case wait(TimeInterval)
}

public struct BrainActor: Sendable {
  public var position: CGPoint
  public var holding: ItemID?
  public var isSubagent: Bool
  /// A sub-agent's parent position and the radius it stays within.
  public var anchor: CGPoint?
  public var leash: CGFloat
  /// What she is heading to or working on, so a drag of that item can re-target her.
  public var task: (item: ItemID, move: Move)?
  /// Where the other Claudettes' feet are, and how much room she gives them.
  public var others: [CGPoint]
  public var gap: CGFloat

  public init(
    position: CGPoint, holding: ItemID? = nil, isSubagent: Bool = false, anchor: CGPoint? = nil,
    leash: CGFloat = 0, task: (item: ItemID, move: Move)? = nil, others: [CGPoint] = [],
    gap: CGFloat = 0
  ) {
    self.others = others
    self.gap = gap
    self.position = position
    self.holding = holding
    self.isSubagent = isSubagent
    self.anchor = anchor
    self.leash = leash
    self.task = task
  }
}

public enum BrainEvent: Sendable {
  case toolStarted(Item, isNew: Bool, move: Move)
  case thinkingChanged(Bool)
  /// Nothing to do: sub-agents drift back inside their leash.
  case idle
  /// A dodge ended at this spot (she was carrying something, if `holding`).
  case dodge(to: CGPoint)
  case itemMoved(ItemID)
  case sessionEnded
}

/// Pure planner: events and snapshots in, intents out. No timers, no UI.
public struct Brain: Sendable {
  /// Closer than this to an item, she reads it where she stands.
  public var reach: CGFloat = 90
  /// How far from an item she stops when she walks to it.
  public var standOff: CGFloat = 60
  public var wanderRadius: CGFloat = 220
  public var tossRange: ClosedRange<CGFloat> = 80...140
  static let screenMargin: CGFloat = 30

  public init() {}

  public static func move(for scene: ToolScene) -> Move {
    switch scene {
    case .read, .web, .skill: return .read
    case .edit, .write, .shell, .mcp: return .typing
    case .search: return .search
    case .todo, .plan, .subagent: return .think
    case .other: return .shrug
    }
  }

  public func plan(
    event: BrainEvent, actor: BrainActor, world: [Item], screens: [CGRect],
    rng: inout some RandomNumberGenerator
  ) -> [Intent] {
    let here = fit(actor.position, screens)
    switch event {
    case .toolStarted(let item, _, let move):
      var out: [Intent] = []
      if actor.holding != nil { out.append(.putDown(at: here)) }
      guard let pos = item.position, pos.x.isFinite, pos.y.isFinite else {
        return out + [.play(move)]
      }
      return out
        + work(
          item, at: pos, move: move, here: here, world: world, screens: screens,
          others: actor.others, gap: actor.gap, rng: &rng)
    case .itemMoved(let id):
      guard let task = actor.task, task.item == id,
        let pos = world.first(where: { $0.id == id })?.position, pos.x.isFinite, pos.y.isFinite
      else { return [] }
      guard let item = world.first(where: { $0.id == id }) else { return [] }
      return work(
        item, at: pos, move: task.move, here: here, world: world, screens: screens,
        others: actor.others, gap: actor.gap, rng: &rng)
    case .thinkingChanged(let on):
      guard on else { return [] }
      return wander(actor: actor, here: here, screens: screens, rng: &rng)
    case .idle:
      guard actor.isSubagent, let anchor = actor.anchor, actor.leash > 0,
        distance(here, anchor) > actor.leash
      else { return [] }
      let back = toward(anchor, from: here, distance: actor.leash * 0.7)
      return [.walk(to: fit(back, screens))]
    case .dodge(let end):
      return actor.holding == nil ? [] : [.putDown(at: fit(end, screens))]
    case .sessionEnded:
      return actor.holding == nil ? [] : [.putDown(at: here)]
    }
  }

  /// Walk next to the item if it is out of reach, face it, pick it up, work on it, then toss it a
  /// little way off (she holds it meanwhile, so a shy dodge carries it along).
  private func work(
    _ item: Item, at pos: CGPoint, move: Move, here: CGPoint, world: [Item], screens: [CGRect],
    others: [CGPoint], gap: CGFloat, rng: inout some RandomNumberGenerator
  ) -> [Intent] {
    var out: [Intent] = []
    if distance(here, pos) > reach {
      out.append(
        .walk(
          to: fit(
            Separation.standSpot(
              target: pos, from: here, standOff: standOff, avoiding: others, minGap: gap),
            screens)))
    }
    out += [.face(pos), .pickUp(item.id), .play(move)]
    let angle = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
    let dist = CGFloat.random(in: tossRange, using: &rng)
    let aim = CGPoint(x: pos.x + dist * cos(angle), y: pos.y + dist * sin(angle))
    let spot = Scatter.spot(
      near: aim, existing: world.filter { $0.id != item.id }.compactMap(\.position),
      itemSize: CGSize(width: 104, height: 80), screens: screens, seed: rng.next())
    out.append(.toss(item.id, to: spot))
    return out
  }

  private func wander(
    actor: BrainActor, here: CGPoint, screens: [CGRect], rng: inout some RandomNumberGenerator
  ) -> [Intent] {
    let leashed = actor.isSubagent && actor.leash > 0 && actor.anchor != nil
    let center = leashed ? actor.anchor! : here
    let radius = leashed ? actor.leash : wanderRadius
    var out: [Intent] = [.play(.think)]
    for _ in 0..<3 {
      let angle = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
      let r = radius * CGFloat.random(in: 0.3...1, using: &rng)
      let p = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
      out.append(
        .walk(to: fit(Separation.push(p, awayFrom: actor.others, minGap: actor.gap), screens)))
      out.append(.wait(TimeInterval.random(in: 0.8...2.2, using: &rng)))
    }
    return out
  }

  /// The point `distance` away from `target`, on the side `from` is on.
  private func toward(_ target: CGPoint, from: CGPoint, distance d: CGFloat) -> CGPoint {
    let dx = from.x - target.x
    let dy = from.y - target.y
    let len = hypot(dx, dy)
    let (ux, uy) = len > 1 ? (dx / len, dy / len) : (-1, 0)
    return CGPoint(x: target.x + ux * d, y: target.y + uy * d)
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

  /// Non-finite becomes the first screen's centre; everything is pulled inside the nearest screen.
  private func fit(_ p: CGPoint, _ screens: [CGRect]) -> CGPoint {
    guard let first = screens.first else { return p }
    let q = CGPoint(
      x: p.x.isFinite ? p.x : first.midX, y: p.y.isFinite ? p.y : first.midY)
    let area =
      screens.first { $0.contains(q) }
      ?? screens.min { dist(q, $0) < dist(q, $1) } ?? first
    let r = area.insetBy(
      dx: min(Self.screenMargin, area.width / 2), dy: min(Self.screenMargin, area.height / 2))
    return CGPoint(x: min(max(q.x, r.minX), r.maxX), y: min(max(q.y, r.minY), r.maxY))
  }

  private func dist(_ p: CGPoint, _ r: CGRect) -> CGFloat {
    hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
  }
}
