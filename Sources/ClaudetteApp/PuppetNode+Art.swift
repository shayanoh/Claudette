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
    sleepDepth = d
    for n in ["blanket", "night", "moonNew", "twinkle"] {
      for node in children + bodyPivot.children where node.name == n { node.removeFromParent() }
    }
    guard d != .awake else {
      idle()
      return
    }
    sleep()
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

  private func breatheSlowly() {
    let slow = SKAction.sequence([.scaleY(to: 0.95, duration: 4), .scaleY(to: 0.99, duration: 4)])
    slow.timingMode = .easeInEaseOut
    bodyPivot.run(.repeatForever(slow), withKey: "breathe")
  }
}
