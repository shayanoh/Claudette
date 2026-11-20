import CoreGraphics
import Foundation

public struct CleanupAssignment: Equatable, Sendable {
  public var actor: String
  /// Each trip is what she carries to the can in one go (at most three items).
  public var trips: [[ItemID]]
}

/// Plans who collects what for a cleanup scene. Pure: positions in, assignments and a time out.
public enum CleanupPlanner {
  public static let walkSpeed: CGFloat = 140
  /// Seconds to pick up and drop one item (the clumsy business included).
  static let handling: TimeInterval = 1.2
  static let maxPerTrip = 3
  public static let durationRange: ClosedRange<TimeInterval> = 10...30

  public static func plan(
    items: [Item], actors: [String: CGPoint], can: CGPoint, now: Date
  ) -> (assignments: [CleanupAssignment], duration: TimeInterval) {
    guard !items.isEmpty, !actors.isEmpty else { return ([], 0) }
    let names = actors.keys.sorted()
    func point(_ i: Item) -> CGPoint {
      guard let p = i.position, p.x.isFinite, p.y.isFinite else { return can }
      return p
    }
    func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // Nearest actor, with a load penalty so one Claudette does not do everything.
    var mine: [String: [Item]] = [:]
    for item in items.sorted(by: { $0.id.raw < $1.id.raw }) {
      let chosen = names.min { a, b in
        let la = dist(actors[a]!, point(item)) + 150 * CGFloat(mine[a]?.count ?? 0)
        let lb = dist(actors[b]!, point(item)) + 150 * CGFloat(mine[b]?.count ?? 0)
        return la < lb
      }!
      mine[chosen, default: []].append(item)
    }

    // Each actor visits her items nearest-first; the smallest armful that fits in 30 s.
    func build(perTrip: Int) -> (assignments: [CleanupAssignment], time: TimeInterval) {
      var out: [CleanupAssignment] = []
      var longest: TimeInterval = 0
      for name in names {
        guard var left = mine[name], !left.isEmpty else { continue }
        var at = actors[name]!
        var trips: [[ItemID]] = []
        var time: TimeInterval = 0
        while !left.isEmpty {
          var trip: [Item] = []
          while trip.count < perTrip, !left.isEmpty {
            let i = left.indices.min { dist(at, point(left[$0])) < dist(at, point(left[$1])) }!
            let next = left.remove(at: i)
            time += Double(dist(at, point(next)) / walkSpeed) + handling
            at = point(next)
            trip.append(next)
          }
          time += Double(dist(at, can) / walkSpeed)
          at = can
          trips.append(trip.map(\.id))
        }
        longest = max(longest, time)
        out.append(CleanupAssignment(actor: name, trips: trips))
      }
      return (out, longest)
    }
    var result = build(perTrip: 1)
    for n in 2...maxPerTrip where result.time > durationRange.upperBound {
      result = build(perTrip: n)
    }
    let duration = min(durationRange.upperBound, max(durationRange.lowerBound, result.time))
    return (result.assignments, duration)
  }
}

/// When a Claudette tidies up by herself.
public enum ClutterPolicy {
  /// Items to collect now: only while the session waits for the user, only above the soft limit,
  /// oldest first, down to half the limit; never a running terminal or something another session
  /// also uses.
  public static func autoTidy(
    session: String, owned: [Item], phase: SessionPhase, softLimit: Int, enabled: Bool
  ) -> [ItemID] {
    guard enabled, softLimit > 0 else { return [] }
    switch phase {
    case .needsApproval, .hasQuestion, .idle: break
    default: return []
    }
    let mine = owned.filter { $0.owners.contains(session) }
    guard mine.count > softLimit else { return [] }
    let target = softLimit / 2
    let candidates =
      mine
      .filter { $0.owners == [session] && $0.terminal?.state != .running }
      .sorted { ($0.lastTouched, $0.id.raw) < ($1.lastTouched, $1.id.raw) }
    return Array(candidates.prefix(max(0, mine.count - target))).map(\.id)
  }

  /// What a leaving session's Claudette collects: items nobody else uses.
  public static func sessionEnd(session: String, items: [Item]) -> [ItemID] {
    items.filter { $0.owners == [session] }.map(\.id)
  }
}
