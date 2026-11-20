import AppKit
import SpriteKit

enum Palette {
  static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
  }
  static let body = hex(0xE07C56)
  static let bodyShadow = hex(0xB0503A)
  static let leg = hex(0xC9643F)
  static let ink = hex(0x3A1A12)
  static let eye = hex(0x26100B)
  static let highlight = hex(0xFFE2CF)
  static let blush = hex(0xF0827A)
  static let spark = hex(0xFFB48F)
  static let question = hex(0x7FC8F8)
  static let approval = hex(0xFFC94D)
  static let error = hex(0xE5484D)
  static let success = hex(0x9BE38B)
}

/// Placeholder Claudette built from shapes, following the rig tree in the design notes.
/// Origin is the centre of her feet; units are points at scale 1.0 (about 123 pt tall).
final class PuppetNode: SKNode {
  static let bodySize = CGSize(width: 150, height: 100)
  static let legLength: CGFloat = 23
  static let ink: CGFloat = 4.6

  // Shapes in placeholder mode, sprites when built from the art export.
  var shadow: SKNode = SKNode()
  let bodyPivot = SKNode()
  let face = SKNode()
  var spark: SKNode = SKNode()
  var legs: [SKNode] = []
  var arms: [SKNode] = []
  var eyes: [SKNode] = []
  /// Art only: the smile sprite, hidden at rest.
  var mouth: SKNode?
  private var asleep = false

  override init() {
    super.init()
    if let lib = ArtLibrary.shared {
      buildFromArt(lib)
    } else {
      build()
    }
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  // MARK: Build

  private func shape(
    _ path: CGPath, fill: NSColor, stroke: NSColor? = Palette.ink, width: CGFloat = PuppetNode.ink
  )
    -> SKShapeNode
  {
    let n = SKShapeNode(path: path)
    n.fillColor = fill
    n.strokeColor = stroke ?? .clear
    n.lineWidth = stroke == nil ? 0 : width
    n.lineJoin = .round
    return n
  }

  private func build() {
    let shadowShape = SKShapeNode(ellipseOf: CGSize(width: 150, height: 16))
    shadowShape.fillColor = NSColor.black.withAlphaComponent(0.18)
    shadowShape.strokeColor = .clear
    shadowShape.position = CGPoint(x: 0, y: -2)
    shadowShape.zPosition = -10
    shadowShape.name = "shadow"
    shadow = shadowShape
    addChild(shadow)

    for (i, x) in [-51.0, -22.0, 22.0, 51.0].enumerated() {
      let leg = shape(
        CGPath(
          roundedRect: CGRect(x: -7, y: -Self.legLength, width: 14, height: Self.legLength),
          cornerWidth: 6, cornerHeight: 6, transform: nil), fill: Palette.leg)
      leg.position = CGPoint(x: x, y: Self.legLength)
      leg.zPosition = -1
      leg.name = "leg_\(i)"
      legs.append(leg)
      addChild(leg)
    }

    bodyPivot.position = CGPoint(x: 0, y: Self.legLength)
    bodyPivot.name = "bodyPivot"
    addChild(bodyPivot)

    for (name, sign) in [("arm_L", -1.0), ("arm_R", 1.0)] {
      let rect =
        sign < 0
        ? CGRect(x: -34, y: -11, width: 34, height: 22)
        : CGRect(x: 0, y: -11, width: 34, height: 22)
      let arm = shape(
        CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil),
        fill: Palette.body)
      arm.position = CGPoint(x: sign * 70, y: 52)
      arm.zPosition = 0
      arm.name = name
      arms.append(arm)
      bodyPivot.addChild(arm)
    }

    let b = Self.bodySize
    let body = shape(
      CGPath(
        roundedRect: CGRect(x: -b.width / 2, y: 0, width: b.width, height: b.height),
        cornerWidth: 16, cornerHeight: 16, transform: nil), fill: Palette.body)
    body.zPosition = 1
    body.name = "body"
    bodyPivot.addChild(body)

    // Hard cel shadow along the bottom, square on top, rounded at the bottom corners.
    let inset = Self.ink / 2
    let left = -b.width / 2 + inset
    let right = b.width / 2 - inset
    let shade = CGMutablePath()
    shade.move(to: CGPoint(x: left, y: 34))
    shade.addLine(to: CGPoint(x: left, y: 16))
    shade.addArc(
      tangent1End: CGPoint(x: left, y: inset), tangent2End: CGPoint(x: left + 14, y: inset),
      radius: 14)
    shade.addLine(to: CGPoint(x: right - 14, y: inset))
    shade.addArc(
      tangent1End: CGPoint(x: right, y: inset), tangent2End: CGPoint(x: right, y: 16), radius: 14)
    shade.addLine(to: CGPoint(x: right, y: 34))
    shade.closeSubpath()
    let shadeNode = shape(shade, fill: Palette.bodyShadow, stroke: nil)
    shadeNode.zPosition = 2
    bodyPivot.addChild(shadeNode)

    let streak = shape(
      CGPath(
        roundedRect: CGRect(x: -58, y: 82, width: 52, height: 8), cornerWidth: 4, cornerHeight: 4,
        transform: nil),
      fill: Palette.highlight, stroke: nil)
    streak.zPosition = 3
    bodyPivot.addChild(streak)

    face.zPosition = 4
    face.name = "face"
    bodyPivot.addChild(face)
    for (name, x) in [("eye_L", -30.0), ("eye_R", 30.0)] {
      let eye = shape(
        CGPath(
          roundedRect: CGRect(x: -8.5, y: -17, width: 17, height: 34), cornerWidth: 8,
          cornerHeight: 8, transform: nil),
        fill: Palette.eye, stroke: nil)
      eye.position = CGPoint(x: x, y: 48)
      eye.name = name
      let glint = shape(
        CGPath(
          roundedRect: CGRect(x: -6, y: 4, width: 7, height: 9), cornerWidth: 3, cornerHeight: 3,
          transform: nil),
        fill: .white, stroke: nil)
      eye.addChild(glint)
      eyes.append(eye)
      face.addChild(eye)
    }
    for x in [-52.0, 52.0] {
      let blush = SKShapeNode(ellipseOf: CGSize(width: 18, height: 10))
      blush.fillColor = Palette.blush.withAlphaComponent(0.8)
      blush.strokeColor = .clear
      blush.position = CGPoint(x: x, y: 32)
      face.addChild(blush)
    }

    let sparkShape = SKShapeNode(path: Self.starPath(points: 8, outer: 14, inner: 6))
    sparkShape.fillColor = Palette.spark
    sparkShape.strokeColor = Palette.ink
    sparkShape.lineWidth = 3
    sparkShape.lineJoin = .round
    spark = sparkShape
    spark.position = CGPoint(x: 0, y: Self.legLength + b.height + 30)
    spark.zPosition = 5
    spark.name = "spark"
    addChild(spark)
  }

  static func starPath(points: Int, outer: CGFloat, inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<(points * 2) {
      let r = i % 2 == 0 ? outer : inner
      let a = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
      let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
      i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
  }

  // MARK: Animation

  /// Breathing, blinking and a bobbing spark. Every other scene sits on top of this.
  func idle() {
    asleep = false
    removeAction(forKey: "z")
    eyes.forEach { $0.yScale = 1 }
    let breathe = SKAction.sequence([
      .scaleY(to: 1.02, duration: 1.2), .scaleY(to: 1.0, duration: 1.2),
    ])
    breathe.timingMode = .easeInEaseOut
    bodyPivot.run(.repeatForever(breathe), withKey: "breathe")
    let blink = SKAction.sequence([
      .wait(forDuration: 3, withRange: 3),
      .run { [weak self] in
        self?.eyes.forEach {
          $0.run(.sequence([.scaleY(to: 0.1, duration: 0.07), .scaleY(to: 1, duration: 0.09)]))
        }
      },
    ])
    face.run(.repeatForever(blink), withKey: "blink")
    let bob = SKAction.sequence([
      .moveBy(x: 0, y: 3, duration: 0.9), .moveBy(x: 0, y: -3, duration: 0.9),
    ])
    bob.timingMode = .easeInEaseOut
    spark.run(.repeatForever(bob), withKey: "bob")
  }

  /// Pops in from nothing, then settles into idle.
  func wake() {
    bodyPivot.removeAllActions()
    alpha = 0
    bodyPivot.xScale = 1.15
    bodyPivot.yScale = 0.3
    run(.fadeIn(withDuration: 0.2))
    bodyPivot.run(
      .sequence([
        .group([.scaleX(to: 0.95, duration: 0.18), .scaleY(to: 1.1, duration: 0.18)]),
        .group([.scaleX(to: 1.0, duration: 0.14), .scaleY(to: 1.0, duration: 0.14)]),
      ])
    ) { [weak self] in self?.idle() }
  }

  /// Eyes shut, slow breathing and floating z's.
  func sleep() {
    asleep = true
    face.removeAction(forKey: "blink")
    eyes.forEach { $0.yScale = 0.12 }
    bodyPivot.removeAction(forKey: "breathe")
    let slow = SKAction.sequence([
      .scaleY(to: 0.93, duration: 2.0), .scaleY(to: 0.97, duration: 2.0),
    ])
    slow.timingMode = .easeInEaseOut
    bodyPivot.run(.repeatForever(slow), withKey: "breathe")
    let z = SKAction.repeatForever(
      .sequence([
        .wait(forDuration: 1.6),
        .run { [weak self] in self?.floatZ() },
      ]))
    run(z, withKey: "z")
  }

  private func floatZ() {
    guard asleep else { return }
    let label = SKLabelNode(text: "z")
    label.fontName = "AvenirNext-Bold"
    label.fontSize = 18
    label.fontColor = Palette.ink
    label.position = CGPoint(x: 60, y: Self.legLength + Self.bodySize.height)
    label.zPosition = 6
    addChild(label)
    label.run(
      .sequence([
        .group([.moveBy(x: 18, y: 34, duration: 1.8), .fadeOut(withDuration: 1.8)]),
        .removeFromParent(),
      ]))
  }

  var isAsleep: Bool { asleep }

  /// Local-space area she occupies (body, arms, legs, shadow); the spark above is not clickable.
  static let hitBounds = CGRect(x: -104, y: -6, width: 208, height: 134)

  // MARK: Reactions to the pointer

  /// Picked up: stretches, legs dangle and swing.
  func grab() {
    asleep = false
    removeAction(forKey: "z")
    eyes.forEach { $0.yScale = 1 }
    bodyPivot.removeAction(forKey: "breathe")
    bodyPivot.run(
      .group([.scaleX(to: 0.93, duration: 0.12), .scaleY(to: 1.1, duration: 0.12)]), withKey: "grab"
    )
    shadow.run(.scale(to: 0.7, duration: 0.12), withKey: "grab")
    for (i, leg) in legs.enumerated() {
      let swing = SKAction.sequence([
        .rotate(toAngle: 0.3 * (i % 2 == 0 ? 1 : -1), duration: 0.18),
        .rotate(toAngle: -0.3 * (i % 2 == 0 ? 1 : -1), duration: 0.18),
      ])
      leg.run(.repeatForever(swing), withKey: "dangle")
    }
  }

  /// Sways opposite to the horizontal motion while being carried.
  func carry(velocityX: CGFloat) {
    let target = max(-0.3, min(0.3, -velocityX * 0.0004))
    run(.rotate(toAngle: target, duration: 0.08), withKey: "carry")
  }

  /// Set down: squash, bounce and shake it off.
  func drop() {
    legs.forEach {
      $0.removeAction(forKey: "dangle")
      $0.run(.rotate(toAngle: 0, duration: 0.1))
    }
    shadow.run(.scale(to: 1, duration: 0.15), withKey: "grab")
    run(.rotate(toAngle: 0, duration: 0.12), withKey: "carry")
    bodyPivot.run(
      .sequence([
        .group([.scaleX(to: 1.12, duration: 0.08), .scaleY(to: 0.82, duration: 0.08)]),
        .group([.scaleX(to: 0.97, duration: 0.1), .scaleY(to: 1.06, duration: 0.1)]),
        .group([.scaleX(to: 1, duration: 0.1), .scaleY(to: 1, duration: 0.1)]),
      ])
    ) { [weak self] in self?.idle() }
  }

  /// A quick hop used when she side-steps the pointer.
  func hop() {
    bodyPivot.run(
      .sequence([
        .group([.scaleX(to: 0.92, duration: 0.07), .scaleY(to: 1.12, duration: 0.07)]),
        .group([.scaleX(to: 1, duration: 0.12), .scaleY(to: 1, duration: 0.12)]),
      ]), withKey: "hop")
    run(
      .sequence([.moveBy(x: 0, y: 14, duration: 0.12), .moveBy(x: 0, y: -14, duration: 0.14)]),
      withKey: "hopLift")
  }

  /// Happy wiggle (petted, task done).
  func happy() {
    eyes.forEach {
      $0.run(
        .sequence([
          .scaleY(to: 0.35, duration: 0.1), .wait(forDuration: 0.8), .scaleY(to: 1, duration: 0.1),
        ]))
    }
    let wiggle = SKAction.sequence([
      .rotate(toAngle: 0.08, duration: 0.1), .rotate(toAngle: -0.08, duration: 0.1),
    ])
    run(
      .sequence([.repeat(wiggle, count: 3), .rotate(toAngle: 0, duration: 0.1)]), withKey: "happy")
  }

  /// The tappable area in the parent's coordinates (body, legs, arms and spark).
  var hitFrame: CGRect { calculateAccumulatedFrame() }
}
