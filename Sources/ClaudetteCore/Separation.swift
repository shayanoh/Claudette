import CoreGraphics
import Foundation

/// Keeps Claudettes from standing on top of each other.
public enum Separation {
  /// `p` moved away from every point in `others` that is closer than `minGap` (each pushes in
  /// proportion to how deep it is inside the gap). The total push is at most one `minGap`.
  public static func push(_ p: CGPoint, awayFrom others: [CGPoint], minGap: CGFloat) -> CGPoint {
    guard minGap > 0, minGap.isFinite, p.x.isFinite, p.y.isFinite else { return p }
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var coincident = 0
    for o in others where o.x.isFinite && o.y.isFinite {
      let vx = p.x - o.x
      let vy = p.y - o.y
      let d = hypot(vx, vy)
      guard d < minGap else { continue }
      if d < 0.001 {  // exactly on top: each one gets its own direction
        coincident += 1
        dx += CGFloat(cos(Double(coincident) * 2.4)) * minGap * 0.6
        dy += CGFloat(sin(Double(coincident) * 2.4)) * minGap * 0.6
      } else {
        let k = (minGap - d) * 0.6 / d
        dx += vx * k
        dy += vy * k
      }
    }
    let len = hypot(dx, dy)
    if len > minGap {
      dx *= minGap / len
      dy *= minGap / len
    }
    return CGPoint(x: p.x + dx, y: p.y + dy)
  }

  /// Where to stand `standOff` from `target`: on the side `from` is on, or, if somebody is already
  /// there, the nearest spot around the target that is at least `minGap` from everybody; when every
  /// side is taken, the roomiest one.
  public static func standSpot(
    target: CGPoint, from: CGPoint, standOff: CGFloat, avoiding others: [CGPoint], minGap: CGFloat
  ) -> CGPoint {
    let dx = from.x - target.x
    let dy = from.y - target.y
    let base = hypot(dx, dy) > 1 ? atan2(dy, dx) : Double.pi
    let near = others.filter { $0.x.isFinite && $0.y.isFinite }
    func spot(_ offsetDegrees: Double) -> CGPoint {
      let a = Double(base) + offsetDegrees * .pi / 180
      return CGPoint(
        x: target.x + standOff * CGFloat(cos(a)), y: target.y + standOff * CGFloat(sin(a)))
    }
    func room(_ p: CGPoint) -> CGFloat {
      near.map { hypot(p.x - $0.x, p.y - $0.y) }.min() ?? .infinity
    }
    var best = spot(0)
    var bestRoom = room(best)
    for off in [0.0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180] {
      let c = spot(off)
      let r = room(c)
      if r >= minGap { return c }
      if r > bestRoom {
        best = c
        bestRoom = r
      }
    }
    return best
  }
}
