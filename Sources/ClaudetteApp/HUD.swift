import AppKit
import ClaudetteCore
import SpriteKit

// Placeholder visuals for the usage limits, following design/concepts/opus/D-usage-limits.png:
// the 5-hour window is a jar of sparks she carries, the weekly window is a moon that wanes.

enum LimitText {
  static func remaining(until date: Date, now: Date) -> String {
    let mins = max(0, Int(date.timeIntervalSince(now) / 60))
    return mins >= 60 ? "in \(mins / 60)h \(mins % 60)m" : "in \(mins)m"
  }

  static func clock(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
  }

  static func weekday(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "EEE HH:mm"
    return f.string(from: date)
  }

  static func percent(_ state: WindowState) -> String {
    state.usedPercentage.map { "\(Int($0.rounded()))%" } ?? "?"
  }
}

/// The jar of sparks (5-hour window). Fill level = remaining budget.
final class JarNode: SKNode {
  private let liquid = SKShapeNode()
  private let glass = SKShapeNode(
    rect: CGRect(x: -11, y: 0, width: 22, height: 34), cornerRadius: 5)
  private let lid = SKShapeNode(rect: CGRect(x: -13, y: 34, width: 26, height: 8), cornerRadius: 3)
  private let tag = SKShapeNode(
    rect: CGRect(x: -30, y: -14, width: 60, height: 26), cornerRadius: 8)
  private let line1 = SKLabelNode()
  private let line2 = SKLabelNode()

  override init() {
    super.init()
    name = "jar"
    glass.strokeColor = Palette.ink
    glass.lineWidth = 2.5
    glass.fillColor = NSColor.white.withAlphaComponent(0.25)
    glass.zPosition = 1
    liquid.strokeColor = .clear
    liquid.fillColor = Palette.hex(0xF08A4B)
    liquid.zPosition = 0
    lid.fillColor = Palette.bodyShadow
    lid.strokeColor = Palette.ink
    lid.lineWidth = 2.5
    lid.zPosition = 2
    tag.fillColor = Palette.hex(0xFFF8F0)
    tag.strokeColor = Palette.ink
    tag.lineWidth = 1.5
    tag.position = CGPoint(x: 0, y: 62)
    tag.zPosition = 3
    for l in [line1, line2] {
      l.fontName = "AvenirNext-DemiBold"
      l.fontSize = 9
      l.fontColor = Palette.ink
      l.horizontalAlignmentMode = .center
      tag.addChild(l)
    }
    line1.position = CGPoint(x: 0, y: 1)
    line2.position = CGPoint(x: 0, y: -10)
    [liquid, glass, lid, tag].forEach(addChild)
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  func update(_ s: WindowState, now: Date, privacy: Bool) {
    let remaining = s.usedPercentage.map { max(0, min(1, 1 - $0 / 100)) } ?? 0.5
    let h = 30 * CGFloat(remaining)
    liquid.path = CGPath(
      roundedRect: CGRect(x: -9, y: 2, width: 18, height: max(0.1, h)), cornerWidth: 3,
      cornerHeight: 3, transform: nil)
    alpha = s.status == .unknown ? 0.4 : 1
    line1.text = "5h \(LimitText.percent(s))"
    switch (s.status, s.resetsAt) {
    case (.inLimit, let r?): line2.text = "at \(LimitText.clock(r))"
    case (_, let r?): line2.text = LimitText.remaining(until: r, now: now)
    default: line2.text = s.status == .unknown ? "no data" : ""
    }
    removeAction(forKey: "flicker")
    if s.status == .low {
      run(
        .repeatForever(
          .sequence([.fadeAlpha(to: 0.6, duration: 0.25), .fadeAlpha(to: 1, duration: 0.25)])),
        withKey: "flicker")
    }
  }
}

/// The weekly moon: full on reset day, waning as the week is spent.
final class MoonNode: SKNode {
  private let dark = SKShapeNode(circleOfRadius: 20)
  private let lit = SKShapeNode()
  private let label = SKLabelNode()

  override init() {
    super.init()
    name = "moon"
    dark.fillColor = Palette.hex(0x3B3F66)
    dark.strokeColor = Palette.ink
    dark.lineWidth = 2.5
    lit.strokeColor = .clear
    lit.fillColor = Palette.hex(0xFFE9A8)
    lit.zPosition = 1
    label.fontName = "AvenirNext-DemiBold"
    label.fontSize = 10
    label.fontColor = .white
    label.position = CGPoint(x: 0, y: -38)
    addChild(dark)
    addChild(lit)
    addChild(label)
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  /// Lit shape for illuminated fraction `k` in 0...1: the right half-disc plus (gibbous) or minus
  /// (crescent) the half-ellipse bounded by the terminator.
  static func litPath(fraction k: CGFloat, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let xt = (1 - 2 * k) * r
    p.move(to: CGPoint(x: 0, y: r))
    p.addArc(center: .zero, radius: r, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
    p.addCurve(
      to: CGPoint(x: 0, y: r), control1: CGPoint(x: xt * 4 / 3, y: -r),
      control2: CGPoint(x: xt * 4 / 3, y: r))
    p.closeSubpath()
    return p
  }

  func update(_ s: WindowState, now: Date) {
    isHidden = s.status == .unknown
    let k = CGFloat(s.usedPercentage.map { max(0, min(1, 1 - $0 / 100)) } ?? 1)
    lit.path = Self.litPath(fraction: k, radius: 18)
    label.text =
      "wk \(LimitText.percent(s))" + (s.resetsAt.map { " · \(LimitText.weekday($0))" } ?? "")
  }
}

/// Draws the 22x16 menubar glyph: a small jar plus a moon, mirroring the limit state.
enum MenuBarGlyph {
  static func image(five: WindowState, seven: WindowState, dot: NSColor?) -> NSImage {
    NSImage(size: NSSize(width: 34, height: 16), flipped: false) { _ in
      let ink = NSColor.labelColor
      // jar
      let jar = NSBezierPath(
        roundedRect: NSRect(x: 2, y: 1, width: 9, height: 13), xRadius: 2, yRadius: 2)
      ink.setStroke()
      jar.lineWidth = 1.2
      jar.stroke()
      let remaining = five.usedPercentage.map { max(0, min(1, 1 - $0 / 100)) } ?? 0.5
      Palette.hex(0xF08A4B).withAlphaComponent(five.status == .unknown ? 0.4 : 1).setFill()
      NSBezierPath(rect: NSRect(x: 3, y: 2, width: 7, height: 11 * remaining)).fill()
      // moon
      let moon = NSRect(x: 15, y: 2, width: 12, height: 12)
      ink.withAlphaComponent(seven.status == .unknown ? 0.3 : 0.5).setStroke()
      NSBezierPath(ovalIn: moon).stroke()
      let k = CGFloat(seven.usedPercentage.map { max(0, min(1, 1 - $0 / 100)) } ?? 1)
      let path = NSBezierPath(cgPath: MoonNode.litPath(fraction: k, radius: 6))
      var t = AffineTransform(translationByX: moon.midX, byY: moon.midY)
      path.transform(using: t)
      (seven.status == .unknown ? ink.withAlphaComponent(0.3) : ink).setFill()
      path.fill()
      t = AffineTransform.identity
      if let dot {
        dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: 27, y: 9, width: 6, height: 6)).fill()
      }
      return true
    }
  }
}

/// Keeps the jar on every Claudette, the moon in the corner, the night tint, the nap signs and the
/// confetti in step with `LimitsModel`.
final class LimitsHUD {
  private let limits: LimitsModel
  private let stage: Stage
  private let overlay: OverlayController
  private let settings: SettingsStore
  private let moon = MoonNode()
  private var dimmed = false

  /// Called with the new menubar image whenever the limit state may have changed.
  var onGlyph: ((NSImage) -> Void)?

  init(limits: LimitsModel, stage: Stage, overlay: OverlayController, settings: SettingsStore) {
    self.limits = limits
    self.stage = stage
    self.overlay = overlay
    self.settings = settings
    limits.onTransition = { [weak self] kind, _, new in
      if kind == .fiveHour { self?.setNight(new == .inLimit) }
      self?.refresh()
    }
    limits.onLifted = { [weak self] _ in self?.celebrate() }
  }

  func refresh() {
    let now = Date()
    let five = limits.state(.fiveHour)
    let seven = limits.state(.sevenDay)
    for actor in stage.actors.values {
      let jar =
        (actor.puppet.childNode(withName: "jar") as? JarNode)
        ?? {
          let j = JarNode()
          j.position = CGPoint(x: 62, y: PuppetNode.legLength + PuppetNode.bodySize.height)
          actor.puppet.addChild(j)
          return j
        }()
      jar.update(five, now: now, privacy: settings.settings.privacyMode)
      if five.status == .inLimit {
        showSign(on: actor.puppet, until: five.resetsAt)
      } else {
        actor.puppet.childNode(withName: "sign")?.removeFromParent()
      }
    }
    if let id = overlay.mainDisplayID, let scene = overlay.overlays[id]?.scene {
      if moon.parent !== scene { scene.addChild(moon) }
      moon.position = CGPoint(
        x: scene.size.width - 80, y: scene.size.height - 90)
      moon.update(seven, now: now)
      moon.isHidden = moon.isHidden || stage.actors.isEmpty
    }
    onGlyph?(
      MenuBarGlyph.image(five: five, seven: seven, dot: statusDot()))
  }

  private func statusDot() -> NSColor? {
    if limits.state(.fiveHour).status == .inLimit || limits.state(.sevenDay).status == .inLimit {
      return Palette.error
    }
    return nil
  }

  private func showSign(on puppet: SKNode, until: Date?) {
    guard puppet.childNode(withName: "sign") == nil else { return }
    let text = until.map { "gone napping · back at \(LimitText.clock($0))" } ?? "gone napping"
    let label = SKLabelNode(text: text)
    label.fontName = "AvenirNext-DemiBold"
    label.fontSize = 11
    label.fontColor = Palette.ink
    label.verticalAlignmentMode = .center
    let w = label.frame.width + 16
    let sign = SKShapeNode(rect: CGRect(x: -w / 2, y: -12, width: w, height: 24), cornerRadius: 8)
    sign.name = "sign"
    sign.fillColor = Palette.hex(0xFFF8F0)
    sign.strokeColor = Palette.ink
    sign.lineWidth = 1.5
    sign.position = CGPoint(x: -30, y: PuppetNode.hitBounds.maxY + 88)
    sign.zPosition = 10
    sign.addChild(label)
    puppet.addChild(sign)
  }

  private func setNight(_ on: Bool) {
    guard on != dimmed else { return }
    stage.noteActivity()
    dimmed = on
    for o in overlay.overlays.values {
      o.scene.childNode(withName: "night")?.removeFromParent()
      guard on else { continue }
      let night = SKSpriteNode(color: Palette.hex(0x1D2440), size: o.scene.size)
      night.name = "night"
      night.anchorPoint = .zero
      night.zPosition = -100
      night.alpha = 0
      o.scene.addChild(night)
      night.run(.fadeAlpha(to: 0.4, duration: 1.0))
    }
    for a in stage.actors.values {
      if on { a.puppet.sleep() } else { a.puppet.idle() }
    }
  }

  private func celebrate() {
    stage.noteActivity()
    for a in stage.actors.values { a.puppet.happy() }
    if settings.settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      return
    }
    for o in overlay.overlays.values { Self.confetti(in: o.scene) }
  }

  static func confetti(in scene: SKScene) {
    let colors = [0xFFB48F, 0x7FC8F8, 0xFFC94D, 0x9BE38B, 0xE5484D, 0xB79CFF].map {
      Palette.hex(UInt32($0))
    }
    for _ in 0..<70 {
      let piece = SKSpriteNode(color: colors.randomElement()!, size: CGSize(width: 8, height: 4))
      piece.position = CGPoint(x: .random(in: 0...scene.size.width), y: scene.size.height + 10)
      piece.zRotation = .random(in: 0...(.pi))
      piece.zPosition = 80
      scene.addChild(piece)
      let fall = Double.random(in: 1.6...3.2)
      piece.run(
        .sequence([
          .wait(forDuration: .random(in: 0...0.6)),
          .group([
            .moveBy(x: .random(in: -80...80), y: -(scene.size.height + 40), duration: fall),
            .rotate(byAngle: .random(in: -6...6), duration: fall),
            .sequence([.wait(forDuration: fall * 0.7), .fadeOut(withDuration: fall * 0.3)]),
          ]),
          .removeFromParent(),
        ]))
    }
  }
}
