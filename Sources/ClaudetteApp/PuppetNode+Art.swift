import AppKit
import ClaudetteCore
import SpriteKit

extension PuppetNode {
  /// Builds the same node tree as the placeholder `build()` from the art export. Infallible:
  /// `ArtLibrary` only exists when every required character texture loaded.
  func buildFromArt(_ lib: ArtLibrary) {
    func part(_ name: String, in parent: SKNode) -> SKNode {
      let n = lib.sprite(name) ?? SKNode()
      parent.addChild(n)
      return n
    }
    shadow = part("shadow", in: self)
    for i in 0..<4 { legs.append(part("leg_\(i)", in: self)) }

    bodyPivot.position = CGPoint(x: 0, y: Self.legLength)
    bodyPivot.name = "bodyPivot"
    addChild(bodyPivot)
    arms = [part("arm_L", in: bodyPivot), part("arm_R", in: bodyPivot)]
    _ = part("body", in: bodyPivot)

    face.zPosition = 4
    face.name = "face"
    bodyPivot.addChild(face)
    for name in ["blush_L", "blush_R"] { _ = part(name, in: face) }
    eyes = [part("eye_L", in: face), part("eye_R", in: face)]
    mouth = part("mouth", in: face)
    mouth?.isHidden = true  // no mouth at rest

    spark = part("spark", in: self)
  }
}

enum EyeVariant: String { case open, happy, sleep, focus, half }
enum MouthVariant: String { case smile, blep, o, wobble }
enum BodyPose: String {
  case stand, sit
  case sleepCurl = "sleep_curl"
}

extension PuppetNode {
  /// How far the hips sink when the legs are tucked (leg 23 pt long, tucked stub about 9 pt).
  static let tuckDrop: CGFloat = 14

  /// True when the puppet is built from art (texture swaps only exist there).
  var usesArt: Bool { mouth != nil }

  private func swap(_ node: SKNode, base: String, variant: String?) {
    guard let sprite = node as? SKSpriteNode, let lib = ArtLibrary.shared else { return }
    let name = variant.map { "\(base).\($0)" } ?? base
    if let t = lib.texture(name) { sprite.texture = t }
  }

  /// Swaps both eye textures; a no-op for placeholder art or a variant the export lacks.
  func setEyes(_ v: EyeVariant) {
    for (node, base) in zip(eyes, ["eye_L", "eye_R"]) {
      swap(node, base: base, variant: v == .open ? nil : v.rawValue)
    }
  }

  /// Shows a mouth variant, or hides the mouth with `nil`.
  func setMouth(_ v: MouthVariant?) {
    guard let mouth else { return }
    mouth.isHidden = v == nil
    if let v { swap(mouth, base: "mouth", variant: v == .smile ? nil : v.rawValue) }
  }

  /// Swaps the body and legs for a pose (sit, curled sleep, standing).
  func setPose(_ p: BodyPose) {
    guard usesArt, let body = bodyPivot.childNode(withName: "body") else { return }
    swap(body, base: "body", variant: p == .stand ? nil : p.rawValue)
    for (i, leg) in legs.enumerated() {
      swap(leg, base: "leg_\(i)", variant: p == .stand ? nil : "tuck")
    }
    // Tucked legs are stubs: lower the hips so the body rests on the ground instead of hovering.
    let hip = p == .stand ? Self.legLength : Self.legLength - Self.tuckDrop
    bodyPivot.position.y = hip
    legs.forEach { $0.position.y = hip }
  }
}

extension PuppetNode {
  /// Art backpack: the fill sprite is scaled in Y (it is anchored at its bottom edge).
  func setContextArt(_ percent: Double?, lib: ArtLibrary) {
    let bag: SKNode
    if let existing = bodyPivot.childNode(withName: "bag") {
      bag = existing
    } else if let sprite = lib.sprite("bag") {
      if let fill = lib.sprite("bag_fill") {
        fill.name = "fill"
        sprite.addChild(fill)
      }
      bodyPivot.addChild(sprite)
      bag = sprite
    } else {
      return
    }
    guard let percent, percent.isFinite else {
      bag.isHidden = true
      return
    }
    bag.isHidden = false
    bag.childNode(withName: "fill")?.yScale = CGFloat(max(0.02, min(1, percent / 100)))
  }
}

extension PuppetNode {
  /// The usage-limit sleep scene: `.nap` (5-hour limit) is sleep under a blanket in a night patch;
  /// `.deep` (weekly limit) is a curled sleep, slower breathing, a new moon and twinkling stars.
  /// Idempotent; art pieces that are missing from the export are simply left out.
  func setSleepDepth(_ d: SleepDepth) {
    guard d != sleepDepth else { return }
    clearSleepScene()
    sleepDepth = d
    guard d != .awake else {
      idle()
      return
    }
    sleep()
    setPose(.stand)  // a curled pose from deep sleep must not outlive it (deep to nap)
    guard let lib = ArtLibrary.shared else {
      if d == .deep { breatheSlowly() }
      return
    }
    if let night = lib.sprite("night_patch") {
      night.name = "night"
      night.alpha = 0
      addChild(night)
      night.run(.fadeIn(withDuration: 1.0))
    }
    if let blanket = lib.sprite(d == .deep ? "blanket_deep" : "blanket") {
      blanket.name = "blanket"
      bodyPivot.addChild(blanket)
    }
    guard d == .deep else { return }
    setPose(.sleepCurl)
    breatheSlowly()
    if let moon = lib.sprite("moon_new") {
      moon.name = "moonNew"
      moon.position = CGPoint(x: -70, y: Self.legLength + Self.bodySize.height + 58)
      moon.zPosition = 6
      addChild(moon)
    }
    let spots = [(-100.0, 150.0), (-30, 190), (40, 175), (90, 150), (-120, 105)]
    for (i, spot) in spots.enumerated() {
      guard let star = lib.sprite("star_twinkle") else { break }
      star.name = "twinkle"
      star.position = CGPoint(x: spot.0, y: spot.1)
      star.zPosition = 6
      addChild(star)
      star.run(
        .repeatForever(
          .sequence([
            .wait(forDuration: Double(i) * 0.4),
            .fadeAlpha(to: 0.2, duration: 1.1), .fadeAlpha(to: 1, duration: 1.1),
          ])))
    }
  }

  /// Removes the blanket, night patch, moon and stars and forgets the depth. `idle()` calls this, so
  /// anything that wakes her (drag, prompt, wake-up) lets the next `LimitsHUD.refresh` restore the scene.
  func clearSleepScene() {
    sleepDepth = .awake
    for n in ["blanket", "night", "moonNew", "twinkle"] {
      for node in children + bodyPivot.children where node.name == n { node.removeFromParent() }
    }
  }

  private func breatheSlowly() {
    let slow = SKAction.sequence([.scaleY(to: 0.95, duration: 4), .scaleY(to: 0.99, duration: 4)])
    slow.timingMode = .easeInEaseOut
    bodyPivot.run(.repeatForever(slow), withKey: "breathe")
  }
}

extension PuppetNode {
  /// Dresses her for the current model (`.other` takes the outfit off). Idempotent; pieces the
  /// export lacks are left out.
  func setOutfit(_ family: ModelFamily) {
    guard family != outfit else { return }
    outfit = family
    for node in bodyPivot.children where node.name == "outfit" { node.removeFromParent() }
    guard let lib = ArtLibrary.shared, let key = Self.outfitKey(family) else { return }
    for piece in ["head", "body"] {
      guard let sprite = lib.sprite("outfit_\(key)_\(piece)") else { continue }
      sprite.name = "outfit"
      sprite.setScale(0.01)
      bodyPivot.addChild(sprite)
      sprite.run(.scale(to: 1, duration: 0.2))
    }
  }

  private static func outfitKey(_ f: ModelFamily) -> String? {
    switch f {
    case .opus: return "opus"
    case .sonnet: return "sonnet"
    case .haiku: return "haiku"
    case .other: return nil
    }
  }

  /// Tints her scarf with the project's colour. Idempotent; a no-op without scarf art.
  func setAccent(hue: Double) {
    guard accentHue != hue, hue.isFinite, let lib = ArtLibrary.shared, lib.asset("scarf") != nil
    else { return }
    accentHue = hue
    let color = NSColor(hue: CGFloat(hue), saturation: 0.55, brightness: 0.95, alpha: 1)
    var scarf = bodyPivot.childNode(withName: "scarf") as? SKSpriteNode
    if scarf == nil, let new = lib.sprite("scarf") {
      bodyPivot.addChild(new)
      scarf = new
      if let tail = lib.sprite("scarf_tail") {
        tail.name = "scarf_tail"
        tail.colorBlendFactor = 1
        tail.color = color
        bodyPivot.addChild(tail)
        let sway = SKAction.sequence([
          .rotate(toAngle: 0.08, duration: 1.2), .rotate(toAngle: -0.08, duration: 1.2),
        ])
        sway.timingMode = .easeInEaseOut
        tail.run(.repeatForever(sway), withKey: "sway")
      }
    }
    scarf?.colorBlendFactor = 1
    scarf?.color = color
    (bodyPivot.childNode(withName: "scarf_tail") as? SKSpriteNode)?.color = color
  }
}

// MARK: - Walking and working (driven by the world, see Stage+World)

extension PuppetNode {
  /// Alternating leg swing and a small body bounce while she walks across the screen.
  func setWalking(_ on: Bool) {
    let swingKey = "walkLegs"
    let bounceKey = "walkBounce"
    if on {
      guard bodyPivot.action(forKey: bounceKey) == nil else { return }
      let bounce = SKAction.sequence([
        .moveBy(x: 0, y: 4, duration: 0.13), .moveBy(x: 0, y: -4, duration: 0.13),
      ])
      bodyPivot.run(.repeatForever(bounce), withKey: bounceKey)
      for (i, leg) in legs.enumerated() {
        let a: CGFloat = i % 2 == 0 ? 0.3 : -0.3
        leg.run(
          .repeatForever(
            .sequence([.rotate(toAngle: a, duration: 0.13), .rotate(toAngle: -a, duration: 0.13)])),
          withKey: swingKey)
      }
    } else {
      if bodyPivot.action(forKey: bounceKey) != nil {
        bodyPivot.removeAction(forKey: bounceKey)
        // The bounce is relative moves: put the body back on its hips.
        let hip = legs.first?.position.y ?? Self.legLength
        bodyPivot.position.y = hip
      }
      for leg in legs {
        leg.removeAction(forKey: swingKey)
        leg.zRotation = 0
      }
    }
  }

  /// A short at-work beat for a tool call: focused eyes and a little bob, then back to normal.
  func perform(_ move: Move) {
    switch move {
    case .read, .typing, .search:
      setEyes(.focus)
      bodyPivot.run(
        .repeat(
          .sequence([.moveBy(x: 0, y: -3, duration: 0.12), .moveBy(x: 0, y: 3, duration: 0.12)]),
          count: 4), withKey: "work")
      run(
        .sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.setEyes(.open) }]),
        withKey: "workFace")
    case .shrug:
      run(
        .sequence([
          .rotate(toAngle: 0.1, duration: 0.12), .rotate(toAngle: -0.1, duration: 0.12),
          .rotate(toAngle: 0, duration: 0.1),
        ]), withKey: "shrug")
    case .celebrate: happy()
    case .startled: hop()
    case .think, .yawn, .stretch, .trip: break  // later tasks give these their own animation
    }
  }
}

// MARK: - Thinking bubble and the project name tag

extension PuppetNode {
  /// A thought cloud with pulsing dots and a few slow sparkles while Claude is thinking.
  func think(_ on: Bool) {
    childNode(withName: "thought")?.removeFromParent()
    guard on else { return }
    let bubble = SKNode()
    bubble.name = "thought"
    bubble.position = CGPoint(x: 96, y: PuppetNode.hitBounds.maxY + 10)
    bubble.zPosition = 20
    for (i, r) in [4.0, 6.0].enumerated() {
      let dot = SKShapeNode(circleOfRadius: CGFloat(r))
      dot.fillColor = Palette.hex(0xFFF8F0)
      dot.strokeColor = Palette.ink
      dot.lineWidth = 2
      dot.position = CGPoint(x: -20 + CGFloat(i) * 9, y: -22 + CGFloat(i) * 9)
      bubble.addChild(dot)
    }
    let cloud = SKShapeNode(ellipseOf: CGSize(width: 54, height: 34))
    cloud.fillColor = Palette.hex(0xFFF8F0)
    cloud.strokeColor = Palette.ink
    cloud.lineWidth = 2.5
    bubble.addChild(cloud)
    for i in 0..<3 {
      let d = SKShapeNode(circleOfRadius: 3)
      d.fillColor = Palette.ink
      d.strokeColor = .clear
      d.position = CGPoint(x: CGFloat(i - 1) * 12, y: 0)
      d.run(
        .repeatForever(
          .sequence([
            .wait(forDuration: Double(i) * 0.25), .scale(to: 1.5, duration: 0.25),
            .scale(to: 1, duration: 0.25), .wait(forDuration: 0.5 - Double(i) * 0.25),
          ])))
      bubble.addChild(d)
    }
    for i in 0..<3 {
      let sparkle = SKShapeNode(path: PuppetNode.starPath(points: 4, outer: 5, inner: 1.6))
      sparkle.fillColor = Palette.hex(0xFFC94D)
      sparkle.strokeColor = .clear
      sparkle.alpha = 0
      sparkle.position = CGPoint(x: CGFloat(i - 1) * 22, y: 16)
      sparkle.run(
        .repeatForever(
          .sequence([
            .wait(forDuration: Double(i) * 0.9),
            .group([
              .sequence([.fadeIn(withDuration: 0.4), .fadeOut(withDuration: 1.4)]),
              .moveBy(x: 0, y: 22, duration: 1.8),
            ]),
            .move(to: CGPoint(x: CGFloat(i - 1) * 22, y: 16), duration: 0),
            .wait(forDuration: 1.0),
          ])))
      bubble.addChild(sparkle)
    }
    addChild(bubble)
  }

  /// The project (folder or worktree) name under her feet; nil hides it.
  func setNameTag(_ text: String?) {
    let name = "nametag"
    guard let text, let entry = LabelTexture.entry(text, size: 12) else {
      childNode(withName: name)?.run(
        .sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]), withKey: "fade")
      return
    }
    if let existing = childNode(withName: name) as? SKSpriteNode,
      existing.userData?["text"] as? String == text
    {
      existing.removeAction(forKey: "fade")
      existing.alpha = 1
      return
    }
    childNode(withName: name)?.removeFromParent()
    let tag = SKSpriteNode(texture: entry.texture, size: entry.size)
    tag.name = name
    tag.userData = ["text": text]
    tag.anchorPoint = CGPoint(x: 0.5, y: 1)
    tag.position = CGPoint(x: 0, y: LabelTexture.padding - 4)
    tag.zPosition = 30
    tag.alpha = 0
    addChild(tag)
    tag.run(.fadeIn(withDuration: 0.12), withKey: "fade")
  }
}
