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
    case .needsApproval:
      if !badgeArt(ArtNames.bangBubble, text: nil, wave: true) {
        badge(text: "!", color: Palette.approval, wave: true)
      }
    case .hasQuestion:
      if !badgeArt(ArtNames.questionBubble, text: nil, wave: true) {
        badge(text: "?", color: Palette.question, wave: true)
      }
    case .error(let kind):
      if !badgeArt(ArtNames.errorPill(kind), text: Self.errorText(kind), wave: false) {
        badge(text: Self.errorText(kind), color: Palette.error, wave: false, pill: true)
      }
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

  /// Art version of the badge. Returns false (nothing added) when the asset is missing.
  private func badgeArt(_ assetName: String, text: String?, wave: Bool) -> Bool {
    guard let lib = ArtLibrary.shared, let asset = lib.asset(assetName),
      let sprite = lib.sprite(assetName)
    else { return false }
    spark.isHidden = true
    let node = SKNode()
    node.name = "badge"
    // Bubbles are anchored on their tail tip (anchor y 0): the tip sits just above her head.
    node.position =
      asset.anchor[1] == 0
      ? CGPoint(x: 0, y: Self.legLength + Self.bodySize.height + 6) : spark.position
    node.zPosition = 8
    node.addChild(sprite)
    sprite.position = .zero
    if let text, let l = asset.label {
      let label = SKLabelNode(text: text)
      label.fontName = "AvenirNext-Bold"
      label.fontSize = 11
      label.fontColor = .white
      label.verticalAlignmentMode = .center
      label.position = CGPoint(x: l[0], y: l[1])
      label.zPosition = 1
      node.addChild(label)
    }
    node.run(
      .repeatForever(
        .sequence([.moveBy(x: 0, y: 4, duration: 0.5), .moveBy(x: 0, y: -4, duration: 0.5)])))
    addChild(node)
    if wave { startWaving() }
    return true
  }

  private func startWaving() {
    guard let arm = arms.last else { return }
    arm.run(
      .repeatForever(
        .sequence([.rotate(toAngle: 0.9, duration: 0.25), .rotate(toAngle: 0.2, duration: 0.25)])),
      withKey: "wave")
    run(
      .repeatForever(.sequence([.wait(forDuration: 8), .run { [weak self] in self?.hop() }])),
      withKey: "attention")
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
    if wave { startWaving() }
  }

  /// Relieved sigh after an error clears or the context was compacted.
  func relief(_ word: String = "phew") {
    let l = SKLabelNode(text: word)
    l.fontName = "AvenirNext-Bold"
    l.fontSize = 16
    l.fontColor = .white
    l.position = CGPoint(x: -70, y: Self.legLength + Self.bodySize.height + 10)
    l.zPosition = 9
    var floater: SKNode = l
    if let lib = ArtLibrary.shared, let puff = lib.sprite("status_relief") {
      // The puff carries the word: label inside the puff's interior slot.
      let holder = SKNode()
      holder.position = l.position
      holder.zPosition = 9
      l.position = lib.asset("status_relief")?.label.map { CGPoint(x: $0[0], y: $0[1]) } ?? .zero
      l.fontColor = Palette.ink
      l.fontSize = 11
      l.verticalAlignmentMode = .center
      l.zPosition = 1
      puff.position = .zero
      holder.addChild(puff)
      holder.addChild(l)
      floater = holder
    }
    addChild(floater)
    floater.run(
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
    if let lib = ArtLibrary.shared, lib.asset("bag") != nil, lib.asset("bag_fill") != nil {
      setContextArt(percent, lib: lib)
      return
    }
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
