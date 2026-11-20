import CoreGraphics
import Foundation

// All maths here is plain CGPoint/CGRect geometry (origin = a rect's lower-left in AppKit's
// screen space, but nothing depends on the y direction), so it can be unit tested without UI.

/// Keeps sprites on screen, including after a display is unplugged.
public enum ScreenFit {
  /// The sprite's new origin: inside the nearest screen. A sprite bigger than that screen in one
  /// dimension is centred in that dimension. With no screens the origin is returned unchanged.
  public static func clamp(_ origin: CGPoint, size: CGSize, to screens: [CGRect]) -> CGPoint {
    guard let i = nearestScreenIndex(for: origin, size: size, screens: screens) else {
      return origin
    }
    let s = screens[i]
    func fit(_ o: CGFloat, _ len: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
      if len >= hi - lo { return lo + (hi - lo - len) / 2 }
      return min(max(o.isFinite ? o : lo, lo), hi - len)
    }
    return CGPoint(
      x: fit(origin.x, size.width, s.minX, s.maxX), y: fit(origin.y, size.height, s.minY, s.maxY))
  }

  /// Index of the screen nearest to the sprite's centre (nil when there are no screens).
  public static func nearestScreenIndex(for origin: CGPoint, size: CGSize, screens: [CGRect])
    -> Int?
  {
    let c = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    return screens.indices.min { distance(c, to: screens[$0]) < distance(c, to: screens[$1]) }
  }

  private static func distance(_ p: CGPoint, to r: CGRect) -> CGFloat {
    let dx = max(r.minX - p.x, 0, p.x - r.maxX)
    let dy = max(r.minY - p.y, 0, p.y - r.maxY)
    return hypot(dx, dy)
  }
}

/// Where each full-size Claudette stands along the bottom edge of a screen.
public enum Placement {
  static let margin: CGFloat = 24
  static let gap: CGFloat = 12

  /// Origins for up to `cap` sprites (at least one when `count > 0`), right to left, plus how many
  /// did not fit and collapse into the "+N" stack.
  public static func layout(
    count: Int, screen: CGRect, spriteSize: CGSize, cap: Int = 6
  ) -> (full: [CGPoint], overflow: Int) {
    guard count > 0 else { return ([], 0) }
    let slot = spriteSize.width + gap
    let usable = max(0, screen.width - 2 * margin + gap)
    let fit = slot > 0 ? Int(usable / slot) : 0
    let shown = min(count, max(1, cap), max(1, fit))
    let origins = (0..<shown).map { i in
      ScreenFit.clamp(
        CGPoint(
          x: screen.maxX - margin - spriteSize.width - CGFloat(i) * slot, y: screen.minY + margin),
        size: spriteSize, to: [screen])
    }
    return (origins, count - shown)
  }
}

public enum HoverFade {
  public static func opacity(pointerInside: Bool, settings: ClaudetteSettings) -> CGFloat {
    pointerInside && settings.hoverFadeEnabled ? CGFloat(settings.hoverFadeOpacity) : 1.0
  }
}

/// Picks a nearby free spot when the pointer gets close, so she can be played with.
public enum DodgePlanner {
  /// - Returns: the sprite's current origin when the pointer is far enough away (no need to
  ///   move), a new origin to dodge to, or `nil` when she is cornered (no free spot far enough
  ///   from the pointer), in which case the caller falls back to hover fade.
  public static func nextPosition(
    sprite: CGRect, pointer: CGPoint, screens: [CGRect], shyness: Double, otherSprites: [CGRect]
  ) -> CGPoint? {
    let s = shyness.isFinite ? min(1, max(0, shyness)) : 0.5
    let reach = max(sprite.width, sprite.height)
    let trigger = reach * CGFloat(0.5 + 1.5 * s)
    let here = CGPoint(x: sprite.midX, y: sprite.midY)
    if hypot(here.x - pointer.x, here.y - pointer.y) > trigger { return sprite.origin }
    guard !screens.isEmpty, pointer.x.isFinite, pointer.y.isFinite else { return nil }

    let safe = trigger * 1.1
    var best: (origin: CGPoint, travel: CGFloat)?
    for step in [1.0, 1.5, 2.0, 2.5, 3.0] {
      for k in 0..<24 {
        let angle = Double(k) * .pi / 12
        let target = CGPoint(
          x: sprite.origin.x + CGFloat(cos(angle) * step) * reach,
          y: sprite.origin.y + CGFloat(sin(angle) * step) * reach)
        let origin = ScreenFit.clamp(target, size: sprite.size, to: screens)
        let rect = CGRect(origin: origin, size: sprite.size)
        guard screens.contains(where: { $0.contains(rect) }) else { continue }
        guard hypot(rect.midX - pointer.x, rect.midY - pointer.y) >= safe else { continue }
        guard !otherSprites.contains(where: { $0.intersects(rect.insetBy(dx: -8, dy: -8)) })
        else { continue }
        let travel = hypot(origin.x - sprite.origin.x, origin.y - sprite.origin.y)
        if best == nil || travel < best!.travel { best = (origin, travel) }
      }
    }
    return best?.origin
  }
}

/// Velocity from the last 100 ms of a drag, and the inertia glide after letting go.
public struct DragPhysics {
  static let window: TimeInterval = 0.1
  static let friction = 5.0  // per second
  static let stopSpeed: CGFloat = 8  // points per second
  static let maxFrames = 600

  private var samples: [(t: TimeInterval, p: CGPoint)] = []
  private var clock: TimeInterval = 0

  public init() {}

  public mutating func begin(at point: CGPoint) {
    clock = 0
    samples = [(0, point)]
  }

  public mutating func move(to point: CGPoint, dt: TimeInterval) {
    clock += dt.isFinite ? max(0, dt) : 0
    samples.append((clock, point))
    samples.removeAll { $0.t < clock - 2 * Self.window }  // keep memory bounded
  }

  /// Ends the drag and returns the release velocity in points per second.
  public mutating func release() -> CGVector {
    defer { samples = [] }
    let recent = samples.filter { $0.t >= clock - Self.window }
    guard let first = recent.first, let last = recent.last, last.t > first.t else { return .zero }
    let dt = CGFloat(last.t - first.t)
    return CGVector(dx: (last.p.x - first.p.x) / dt, dy: (last.p.y - first.p.y) / dt)
  }

  /// Sprite origins at 60 fps while she slides to a stop, never leaving the screen.
  public static func glide(
    from: CGPoint, velocity: CGVector, screen: CGRect, spriteSize: CGSize
  ) -> [CGPoint] {
    guard velocity.dx.isFinite, velocity.dy.isFinite else { return [from] }
    var p = ScreenFit.clamp(from, size: spriteSize, to: [screen])
    var v = velocity
    var path = [p]
    let dt: CGFloat = 1.0 / 60
    let decay = CGFloat(exp(-friction * Double(dt)))
    let minX = screen.minX
    let maxX = screen.maxX - spriteSize.width
    let minY = screen.minY
    let maxY = screen.maxY - spriteSize.height
    for _ in 0..<maxFrames where hypot(v.dx, v.dy) >= stopSpeed {
      var next = CGPoint(x: p.x + v.dx * dt, y: p.y + v.dy * dt)
      if next.x < minX {
        next.x = minX
        v.dx = 0
      } else if next.x > maxX {
        next.x = maxX
        v.dx = 0
      }
      if next.y < minY {
        next.y = minY
        v.dy = 0
      } else if next.y > maxY {
        next.y = maxY
        v.dy = 0
      }
      v = CGVector(dx: v.dx * decay, dy: v.dy * decay)
      p = next
      path.append(p)
    }
    return path
  }
}

/// The colour of the little status dot on the menubar glyph.
public enum AttentionDot: Equatable, Sendable {
  case approval, question, error

  /// Errors and limits win over approval requests, which win over questions.
  public static func pick(phases: [SessionPhase], inLimit: Bool) -> AttentionDot? {
    if inLimit { return .error }
    var best: AttentionDot?
    for phase in phases {
      switch phase {
      case .error: return .error
      case .needsApproval: best = .approval
      case .hasQuestion: if best == nil { best = .question }
      default: break
      }
    }
    return best
  }
}
