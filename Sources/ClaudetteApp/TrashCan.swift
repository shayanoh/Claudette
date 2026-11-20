import AppKit
import SpriteKit

/// The trash can that slides in for a cleanup and leaves afterwards. Uses the `trash_can` and
/// `trash_lid` art when the export has them, simple shapes otherwise.
final class TrashCanNode: SKNode {
  /// Where items are thrown in, relative to the node.
  static let mouth = CGPoint(x: 0, y: 80)
  /// The lid hinge from the can's anchor (bottom centre), from the art export; it opens clockwise.
  private static let hinge = CGPoint(x: 34, y: 77)
  private let lid = SKNode()
  private let body = SKNode()

  override init() {
    super.init()
    zPosition = 10  // behind every Claudette (they start at 200), above items
    addChild(body)
    if let lib = ArtLibrary.shared, let can = lib.sprite("trash_can"),
      let top = lib.sprite("trash_lid")
    {
      can.position = .zero
      body.addChild(can)
      // Rotate about the hinge: the lid sprite shares the can's canvas, so offset it back.
      lid.position = Self.hinge
      top.position = CGPoint(x: -Self.hinge.x, y: -Self.hinge.y)
      lid.addChild(top)
    } else {
      let bin = SKShapeNode(rect: CGRect(x: -26, y: 0, width: 52, height: 62), cornerRadius: 6)
      bin.fillColor = Palette.hex(0x9AA3B2)
      bin.strokeColor = Palette.ink
      bin.lineWidth = 3
      body.addChild(bin)
      for x in [-12.0, 0, 12] {
        let rib = SKShapeNode(
          rect: CGRect(x: x - 1.5, y: 8, width: 3, height: 44), cornerRadius: 1.5)
        rib.fillColor = Palette.ink.withAlphaComponent(0.35)
        rib.strokeColor = .clear
        body.addChild(rib)
      }
      let cap = SKShapeNode(rect: CGRect(x: -31, y: 0, width: 62, height: 10), cornerRadius: 4)
      cap.fillColor = Palette.hex(0xB7BFCC)
      cap.strokeColor = Palette.ink
      cap.lineWidth = 3
      cap.position = CGPoint(x: 0, y: 62)
      lid.addChild(cap)
      lid.position = .zero
    }
    lid.zPosition = 1
    addChild(lid)
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  /// Slides in from beyond the screen edge to `spot` (scene coordinates).
  func slideIn(to spot: CGPoint, from edgeX: CGFloat) {
    position = CGPoint(x: edgeX, y: spot.y)
    let move = SKAction.move(to: spot, duration: 0.6)
    move.timingMode = .easeOut
    run(move)
  }

  func slideOut(toward edgeX: CGFloat, completion: @escaping () -> Void) {
    let move = SKAction.moveTo(x: edgeX, duration: 0.6)
    move.timingMode = .easeIn
    // The completion is a step, not the action's completion block: that may never fire once the
    // node has been removed from its parent.
    run(.sequence([.wait(forDuration: 0.4), move, .run(completion), .removeFromParent()]))
  }

  /// For previews: holds the lid at an angle (negative opens it).
  func setLidAngle(_ a: CGFloat) { lid.zRotation = a }

  /// Something landed in it: the lid flaps and the whole can jolts.
  func clank() {
    lid.run(
      .sequence([.rotate(toAngle: -0.7, duration: 0.07), .rotate(toAngle: 0, duration: 0.14)]),
      withKey: "clank")
    body.run(
      .sequence([.scaleY(to: 0.93, duration: 0.06), .scaleY(to: 1, duration: 0.1)]),
      withKey: "jolt")
  }
}
