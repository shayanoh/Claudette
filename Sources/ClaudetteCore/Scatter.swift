import CoreGraphics
import Foundation

/// Picks where a new item lands: near the actor, with room around it, spreading wider the more
/// there already is nearby, and always fully on one screen. Deterministic for a seed.
public enum Scatter {
  /// SplitMix64: tiny, seedable, good enough for placement.
  private struct Rng {
    var state: UInt64
    mutating func next() -> Double {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
  }

  /// Centre for a new item of `itemSize`. With no screens, `near` is returned unchanged.
  public static func spot(
    near: CGPoint, existing: [CGPoint], itemSize: CGSize, screens: [CGRect], seed: UInt64
  ) -> CGPoint {
    guard !screens.isEmpty else { return near }
    let w = itemSize.width.isFinite ? max(0, itemSize.width) : 0
    let h = itemSize.height.isFinite ? max(0, itemSize.height) : 0
    let anchor = CGPoint(x: near.x.isFinite ? near.x : 0, y: near.y.isFinite ? near.y : 0)
    let others = existing.filter { $0.x.isFinite && $0.y.isFinite }
    let area = screens.first { $0.contains(anchor) } ?? nearest(to: anchor, screens)
    let bounds = area.insetBy(dx: min(w / 2, area.width / 2), dy: min(h / 2, area.height / 2))

    func clamp(_ p: CGPoint) -> CGPoint {
      CGPoint(
        x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }
    func gap(_ p: CGPoint) -> CGFloat {
      others.map { hypot(p.x - $0.x, p.y - $0.y) }.min() ?? .infinity
    }

    let crowd = others.filter { hypot($0.x - anchor.x, $0.y - anchor.y) < 200 }.count
    var radius = max(w, 24) * 0.9 + 18 * CGFloat(min(crowd, 20))
    var rng = Rng(state: seed)
    var best = clamp(anchor)
    var bestGap = gap(best)
    if bestGap >= w, crowd == 0 { return best }  // nothing nearby: stay put
    for attempt in 0..<48 {
      if attempt > 0, attempt % 6 == 0 { radius *= 1.3 }
      let angle = rng.next() * 2 * .pi
      let r = radius * CGFloat(0.35 + 0.65 * rng.next())
      let p = clamp(
        CGPoint(x: anchor.x + r * CGFloat(cos(angle)), y: anchor.y + r * CGFloat(sin(angle))))
      let g = gap(p)
      if g >= w { return p }
      if g > bestGap {
        best = p
        bestGap = g
      }
    }
    return best
  }

  private static func nearest(to p: CGPoint, _ screens: [CGRect]) -> CGRect {
    func d(_ r: CGRect) -> CGFloat {
      hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
    return screens.min { d($0) < d($1) } ?? screens[0]
  }
}
