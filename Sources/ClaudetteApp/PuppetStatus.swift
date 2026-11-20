import AppKit
import ClaudetteCore
import SpriteKit

extension PuppetNode {
  /// Replaces the spark with a status badge: `!` (needs you), `?` (question), or an error label.
  func setStatus(_ phase: SessionPhase) {
    childNode(withName: "badge")?.removeFromParent()
    removeAction(forKey: "attention")
    arms.last?.removeAction(forKey: "wave")
    arms.last?.zRotation = 0
    spark.isHidden = false
    switch phase {
    case .needsApproval: badge(text: "!", color: Palette.approval, wave: true)
    case .hasQuestion: badge(text: "?", color: Palette.question, wave: true)
    case .error(let kind):
      badge(text: Self.errorText(kind), color: Palette.error, wave: false, pill: true)
    default: break
    }
  }

  static func errorText(_ kind: ErrorKind) -> String {
    switch kind {
    case .api: return "API error"
    case .auth: return "sign in"
    case .billing: return "billing"
    case .rateLimit: return "rate limit"
    case .disconnect: return "offline"
    case .unknown: return "error"
    }
  }

  private func badge(text: String, color: NSColor, wave: Bool, pill: Bool = false) {
    spark.isHidden = true
    let node = SKNode()
    node.name = "badge"
    node.position = spark.position
    node.zPosition = 8
    let bubble: SKShapeNode
    if pill {
      let w = CGFloat(text.count) * 8 + 24
      bubble = SKShapeNode(rect: CGRect(x: -w / 2, y: -13, width: w, height: 26), cornerRadius: 13)
    } else {
      bubble = SKShapeNode(circleOfRadius: 17)
    }
    bubble.fillColor = color
    bubble.strokeColor = Palette.ink
    bubble.lineWidth = 3
    node.addChild(bubble)
    let label = SKLabelNode(text: text)
    label.fontName = "AvenirNext-Bold"
    label.fontSize = pill ? 12 : 22
    label.fontColor = pill ? .white : Palette.ink
    label.verticalAlignmentMode = .center
    node.addChild(label)
    node.run(
      .repeatForever(
        .sequence([.moveBy(x: 0, y: 4, duration: 0.5), .moveBy(x: 0, y: -4, duration: 0.5)])))
    addChild(node)
    guard wave, let arm = arms.last else { return }
    arm.run(
      .repeatForever(
        .sequence([.rotate(toAngle: 0.9, duration: 0.25), .rotate(toAngle: 0.2, duration: 0.25)])),
      withKey: "wave")
    run(
      .repeatForever(.sequence([.wait(forDuration: 8), .run { [weak self] in self?.hop() }])),
      withKey: "attention")
  }

  /// Relieved sigh after an error clears or the context was compacted.
  func relief(_ word: String = "phew") {
    let l = SKLabelNode(text: word)
    l.fontName = "AvenirNext-Bold"
    l.fontSize = 16
    l.fontColor = .white
    l.position = CGPoint(x: -70, y: Self.legLength + Self.bodySize.height + 10)
    l.zPosition = 9
    addChild(l)
    l.run(
      .sequence([
        .group([.moveBy(x: -10, y: 30, duration: 1.2), .fadeOut(withDuration: 1.2)]),
        .removeFromParent(),
      ]))
    bodyPivot.run(
      .sequence([
        .group([.scaleX(to: 1.06, duration: 0.25), .scaleY(to: 0.94, duration: 0.25)]),
        .group([.scaleX(to: 1, duration: 0.3), .scaleY(to: 1, duration: 0.3)]),
      ]), withKey: "relief")
  }

  /// A skill loaded: its name rises as a rune and sparkles swirl into her head.
  func rune(_ name: String) {
    let l = SKLabelNode(text: name.isEmpty ? "✦" : PropNode.shorten(name, 22))
    l.fontName = "AvenirNext-Bold"
    l.fontSize = 13
    l.fontColor = Palette.hex(0xFFE9A8)
    l.position = CGPoint(x: 0, y: Self.legLength + Self.bodySize.height + 70)
    l.zPosition = 9
    addChild(l)
    l.run(
      .sequence([
        .group([.moveBy(x: 0, y: 26, duration: 1.6), .fadeOut(withDuration: 1.6)]),
        .removeFromParent(),
      ]))
    for i in 0..<6 {
      let star = SKShapeNode(path: Self.starPath(points: 4, outer: 6, inner: 2))
      star.fillColor = Palette.hex(0xFFE9A8)
      star.strokeColor = .clear
      let a = CGFloat(i) * .pi / 3
      star.position = CGPoint(
        x: cos(a) * 60, y: Self.legLength + Self.bodySize.height * 0.5 + sin(a) * 50)
      star.zPosition = 9
      addChild(star)
      star.run(
        .sequence([
          .wait(forDuration: Double(i) * 0.08),
          .group([
            .move(to: CGPoint(x: 0, y: Self.legLength + Self.bodySize.height * 0.7), duration: 0.6),
            .scale(to: 0.2, duration: 0.6),
          ]),
          .removeFromParent(),
        ]))
    }
    happy()
  }

  /// Backpack that fills as the context window fills.
  func setContext(_ percent: Double?, privacy: Bool) {
    let bag =
      (bodyPivot.childNode(withName: "bag") as? SKShapeNode)
      ?? {
        let b = SKShapeNode(rect: CGRect(x: -11, y: 0, width: 22, height: 28), cornerRadius: 6)
        b.name = "bag"
        b.fillColor = Palette.hex(0xD8B98A)
        b.strokeColor = Palette.ink
        b.lineWidth = 2.5
        b.position = CGPoint(x: -82, y: 96)
        b.zPosition = -1
        let fill = SKShapeNode()
        fill.name = "fill"
        fill.fillColor = Palette.hex(0xE07C56)
        fill.strokeColor = .clear
        b.addChild(fill)
        bodyPivot.addChild(b)
        return b
      }()
    guard let percent else {
      bag.isHidden = true
      return
    }
    bag.isHidden = false
    let h = 24 * CGFloat(max(0, min(100, percent)) / 100)
    (bag.childNode(withName: "fill") as? SKShapeNode)?.path = CGPath(
      roundedRect: CGRect(x: -9, y: 2, width: 18, height: max(0.1, h)), cornerWidth: 3,
      cornerHeight: 3, transform: nil)
  }

  /// Compaction: squash the backpack down with a sigh.
  func compact() {
    relief("squish")
    bodyPivot.childNode(withName: "bag")?.run(
      .sequence([.scale(to: 0.7, duration: 0.15), .scale(to: 1, duration: 0.3)]))
  }
}
