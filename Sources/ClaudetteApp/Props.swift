import AppKit
import ClaudetteCore
import SpriteKit

/// A placeholder prop for a tool call (paper for Read, pencil for Edit, terminal for Bash, a
/// cartridge with a cable for MCP, ...). Final art replaces these in the art plan.
final class PropNode: SKNode {
  let toolScene: ToolScene
  let cable = SKShapeNode()
  /// Coloured core of the MCP cable (art mode); `cable` is then its ink outline.
  let cableCore = SKShapeNode()
  /// Connector plug at the cable's end (art mode).
  var plug: SKSpriteNode?
  let body = SKNode()

  init(scene: ToolScene, privacy: Bool) {
    toolScene = scene
    super.init()
    cable.strokeColor = Palette.ink
    cable.lineWidth = 3
    cable.zPosition = -1
    cableCore.strokeColor = .clear
    addChild(cable)
    addChild(cableCore)
    addChild(body)
    if let lib = ArtLibrary.shared, buildArt(scene, privacy: privacy, lib: lib) { return }
    build(scene, privacy: privacy)
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  /// Points the MCP cable at `target` (in this node's coordinates).
  func setCableEnd(_ target: CGPoint) {
    guard case .mcp = toolScene else { return }
    let p = CGMutablePath()
    p.move(to: .zero)
    p.addQuadCurve(to: target, control: CGPoint(x: target.x * 0.4, y: -28))
    cable.path = p
    cableCore.path = p
    if let plug {
      // Aim the plug along the curve's end tangent (control point to target).
      let c = CGPoint(x: target.x * 0.4, y: -28)
      plug.position = target
      plug.zRotation = atan2(target.y - c.y, target.x - c.x) + .pi
    }
  }

  private func shape(_ rect: CGRect, radius: CGFloat = 4, fill: NSColor, stroke: Bool = true)
    -> SKShapeNode
  {
    let n = SKShapeNode(rect: rect, cornerRadius: radius)
    n.fillColor = fill
    n.strokeColor = stroke ? Palette.ink : .clear
    n.lineWidth = 2.5
    return n
  }

  func label(_ text: String, y: CGFloat = -34, size: CGFloat = 10) {
    let l = SKLabelNode(text: text)
    l.fontName = "AvenirNext-DemiBold"
    l.fontSize = size
    l.fontColor = .white
    l.verticalAlignmentMode = .top
    l.position = CGPoint(x: 0, y: y)
    // dark outline for legibility on any wallpaper
    let outline = SKLabelNode(text: text)
    outline.fontName = l.fontName
    outline.fontSize = size
    outline.fontColor = Palette.ink
    outline.verticalAlignmentMode = .top
    outline.position = CGPoint(x: 1, y: y - 1)
    body.addChild(outline)
    body.addChild(l)
  }

  static func shorten(_ s: String, _ n: Int = 16) -> String {
    s.count > n ? String(s.prefix(n - 1)) + "…" : s
  }

  func name(_ s: String?, _ privacy: Bool) -> String {
    guard let s, !s.isEmpty else { return "" }
    return privacy ? "•••" : Self.shorten(s)
  }

  static func initials(_ s: String) -> String {
    let parts = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    return String(parts.prefix(2).compactMap(\.first)).uppercased()
  }

  private func build(_ scene: ToolScene, privacy: Bool) {
    switch scene {
    case .read(let file):
      body.addChild(
        shape(CGRect(x: -17, y: -22, width: 34, height: 44), fill: Palette.hex(0xFFF8F0)))
      for i in 0..<4 {
        body.addChild(
          shape(
            CGRect(x: -11, y: 12 - CGFloat(i) * 9, width: 22 - CGFloat(i % 2) * 6, height: 3),
            radius: 1, fill: Palette.hex([0xE07C56, 0x7FA3D6, 0x8FBF7F, 0xB0B0B0][i]), stroke: false
          ))
      }
      label(name(file, privacy))
    case .search:
      let lens = SKShapeNode(circleOfRadius: 13)
      lens.fillColor = Palette.question.withAlphaComponent(0.4)
      lens.strokeColor = Palette.ink
      lens.lineWidth = 3.5
      body.addChild(lens)
      let handle = SKShapeNode(rect: CGRect(x: 9, y: -22, width: 5, height: 16), cornerRadius: 2)
      handle.fillColor = Palette.ink
      handle.zRotation = .pi / 4
      handle.position = CGPoint(x: 4, y: -2)
      body.addChild(handle)
      label("search")
    case .edit(let file), .write(let file):
      body.addChild(
        shape(CGRect(x: -17, y: -20, width: 34, height: 40), fill: Palette.hex(0xFFF8F0)))
      let pencil = shape(
        CGRect(x: -4, y: -4, width: 8, height: 34), radius: 2, fill: Palette.approval)
      pencil.zRotation = -0.6
      pencil.position = CGPoint(x: 14, y: 6)
      body.addChild(pencil)
      pencil.run(
        .repeatForever(
          .sequence([.moveBy(x: -5, y: -3, duration: 0.18), .moveBy(x: 5, y: 3, duration: 0.18)])))
      label(name(file, privacy))
    case .shell(let long, let background):
      body.addChild(
        shape(CGRect(x: -23, y: -16, width: 46, height: 32), fill: Palette.hex(0x1F1B18)))
      let prompt = SKLabelNode(text: "$ _")
      prompt.fontName = "Menlo-Bold"
      prompt.fontSize = 11
      prompt.fontColor = Palette.success
      prompt.verticalAlignmentMode = .center
      body.addChild(prompt)
      if long {
        let spinner = SKShapeNode(circleOfRadius: 7)
        spinner.strokeColor = Palette.approval
        spinner.lineWidth = 3
        spinner.fillColor = .clear
        spinner.position = CGPoint(x: 0, y: 30)
        spinner.path = CGPath(
          ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14), transform: nil)
        spinner.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1)))
        let arc = SKShapeNode()
        let p = CGMutablePath()
        p.addArc(center: .zero, radius: 7, startAngle: 0, endAngle: .pi * 1.4, clockwise: false)
        arc.path = p
        arc.strokeColor = Palette.approval
        arc.lineWidth = 3
        arc.position = CGPoint(x: 0, y: 30)
        arc.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 1)))
        body.addChild(arc)
      }
      label(background ? "background" : (long ? "still running…" : "running"))
    case .web:
      let plane = SKShapeNode()
      let p = CGMutablePath()
      p.move(to: CGPoint(x: -20, y: -6))
      p.addLine(to: CGPoint(x: 22, y: 6))
      p.addLine(to: CGPoint(x: -6, y: 14))
      p.addLine(to: CGPoint(x: -4, y: 2))
      p.closeSubpath()
      plane.path = p
      plane.fillColor = Palette.hex(0xFFF8F0)
      plane.strokeColor = Palette.ink
      plane.lineWidth = 2.5
      plane.lineJoin = .round
      body.addChild(plane)
      plane.run(
        .repeatForever(
          .sequence([.moveBy(x: 6, y: 4, duration: 0.6), .moveBy(x: -6, y: -4, duration: 0.6)])))
      label("web")
    case .skill(let skill):
      body.addChild(
        shape(CGRect(x: -18, y: -22, width: 36, height: 44), fill: Palette.hex(0x7B8FD1)))
      body.addChild(
        shape(
          CGRect(x: -18, y: -22, width: 7, height: 44), radius: 2, fill: Palette.hex(0x5A6CB0),
          stroke: false))
      let gem = SKShapeNode(circleOfRadius: 3)
      gem.fillColor = Palette.approval
      gem.strokeColor = .clear
      gem.position = CGPoint(x: 4, y: 4)
      body.addChild(gem)
      label(name(skill, privacy))
    case .mcp(let server, _):
      let hue = CGFloat(abs(server.hashValue % 360)) / 360
      body.addChild(
        shape(
          CGRect(x: -17, y: -20, width: 34, height: 40),
          fill: NSColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1)))
      let tag = SKLabelNode(text: privacy ? "••" : Self.initials(server))
      tag.fontName = "AvenirNext-Bold"
      tag.fontSize = 14
      tag.fontColor = Palette.ink
      tag.verticalAlignmentMode = .center
      body.addChild(tag)
      label(name(server, privacy))
    case .todo:
      body.addChild(
        shape(CGRect(x: -17, y: -22, width: 34, height: 44), fill: Palette.hex(0xD8B98A)))
      for i in 0..<3 {
        body.addChild(
          shape(
            CGRect(x: -11, y: 10 - CGFloat(i) * 11, width: 6, height: 6), radius: 1,
            fill: i < 2 ? Palette.success : .white))
      }
      label("todo")
    case .plan:
      body.addChild(
        shape(CGRect(x: -22, y: -14, width: 44, height: 28), fill: Palette.hex(0x3A6EA5)))
      for i in 0..<3 {
        body.addChild(
          shape(
            CGRect(x: -16, y: 6 - CGFloat(i) * 7, width: 32, height: 1.5), radius: 0.5,
            fill: .white, stroke: false))
      }
      label("plan")
    case .subagent:
      break  // the mini-Claudette is the visual
    case .other(let tool):
      let gear = SKShapeNode(path: PuppetNode.starPath(points: 8, outer: 16, inner: 11))
      gear.fillColor = Palette.hex(0xB0B0B0)
      gear.strokeColor = Palette.ink
      gear.lineWidth = 2.5
      body.addChild(gear)
      gear.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 4)))
      label(name(tool, privacy))
    }
  }
}
