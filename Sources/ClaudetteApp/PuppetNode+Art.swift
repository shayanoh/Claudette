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
