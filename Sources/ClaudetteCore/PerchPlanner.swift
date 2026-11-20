import CoreGraphics
import Foundation

/// A window's frame as the window server reports it, converted to the stage's coordinates (origin
/// bottom-left, so the top edge is `maxY`). Lists are ordered front to back.
public struct WindowFrame: Equatable, Sendable {
  public var number: Int
  public var frame: CGRect
  public var layer: Int
  public var ownerPID: Int32

  public init(number: Int, frame: CGRect, layer: Int, ownerPID: Int32) {
    self.number = number
    self.frame = frame
    self.layer = layer
    self.ownerPID = ownerPID
  }
}

/// Where Claudette may sit on a window's top edge, and when the window was pulled from under her.
public enum PerchPlanner {
  /// Keeps her feet clear of rounded corners.
  static let edgeInset: CGFloat = 30
  /// Room she needs above the edge (about her height).
  static let headroom: CGFloat = 140

  /// The nearest free top edge within `reach`: an ordinary (layer 0) window of another app, big
  /// enough, not hidden by a window in front at that spot, with headroom on its screen.
  public static func candidate(
    near: CGPoint, windows: [WindowFrame], screens: [CGRect], ownPID: Int32, minSize: CGSize,
    reach: CGFloat
  ) -> (window: Int, spot: CGPoint)? {
    guard near.x.isFinite, near.y.isFinite else { return nil }
    var best: (window: Int, spot: CGPoint, distance: CGFloat)?
    for (i, w) in windows.enumerated() {
      guard w.layer == 0, w.ownerPID != ownPID, isUsable(w.frame, minSize: minSize)
      else { continue }
      let lo = w.frame.minX + edgeInset
      let hi = w.frame.maxX - edgeInset
      guard hi >= lo else { continue }
      let spot = CGPoint(x: Swift.min(Swift.max(near.x, lo), hi), y: w.frame.maxY)
      let d = hypot(near.x - spot.x, near.y - spot.y)
      guard d <= reach, d < (best?.distance ?? .infinity) else { continue }
      guard hasHeadroom(spot, screens: screens), !isCovered(spot, by: windows.prefix(i)) else {
        continue
      }
      best = (w.number, spot, d)
    }
    return best.map { ($0.window, $0.spot) }
  }

  /// True when the perch is gone: the window vanished, its top edge or left edge or width changed
  /// by more than `tolerance`, or a window in front now hides the spot.
  public static func moved(
    perched: WindowFrame, spot: CGPoint, now: [WindowFrame], tolerance: CGFloat
  ) -> Bool {
    guard let i = now.firstIndex(where: { $0.number == perched.number }) else { return true }
    let f = now[i].frame
    let p = perched.frame
    if abs(f.maxY - p.maxY) > tolerance || abs(f.minX - p.minX) > tolerance
      || abs(f.width - p.width) > tolerance
    {
      return true
    }
    return isCovered(spot, by: now.prefix(i))
  }

  private static func isUsable(_ f: CGRect, minSize: CGSize) -> Bool {
    f.width.isFinite && f.height.isFinite && f.origin.x.isFinite && f.origin.y.isFinite
      && f.width >= minSize.width && f.height >= minSize.height
  }

  private static func hasHeadroom(_ spot: CGPoint, screens: [CGRect]) -> Bool {
    guard let s = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(spot) }) else {
      return false
    }
    return s.maxY - spot.y >= headroom
  }

  /// A window in front covers the edge when it contains the point just under the spot.
  private static func isCovered(_ spot: CGPoint, by front: ArraySlice<WindowFrame>) -> Bool {
    let probe = CGPoint(x: spot.x, y: spot.y - 2)
    return front.contains { $0.layer == 0 && $0.frame.contains(probe) }
  }
}
