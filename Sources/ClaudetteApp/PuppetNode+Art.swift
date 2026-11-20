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
