import AppKit
import ClaudetteCore
import SpriteKit

extension PropNode {
  /// Builds the prop from the art export. Returns false (nothing added) when the asset for this
  /// scene is missing, so the caller falls back to the placeholder shapes.
  func buildArt(_ scene: ToolScene, privacy: Bool, lib: ArtLibrary) -> Bool {
    guard let assetName = ArtNames.prop(for: scene), let asset = lib.asset(assetName),
      let sprite = lib.sprite(assetName)
    else { return false }
    body.addChild(sprite)
    let half = CGFloat(asset.size[1]) / 2

    if let text = captionText(scene, privacy: privacy), !text.isEmpty {
      label(text, y: asset.label.map { CGFloat($0[1]) } ?? -(half + 5))
    }

    switch scene {
    case .edit, .write:
      if let pencil = lib.sprite("prop_edit_pencil") {
        pencil.position = CGPoint(x: 6, y: -6)
        pencil.zRotation = -0.5
        pencil.zPosition = 1
        body.addChild(pencil)
        pencil.run(
          .repeatForever(
            .sequence([.moveBy(x: -5, y: -3, duration: 0.18), .moveBy(x: 5, y: 3, duration: 0.18)])
          ))
      }
    case .shell(let long, _):
      // The spinner socket on prop_shell_long is 15 pt above its anchor (not in the manifest).
      if long { addSpinner(y: 15) }
    case .web:
      sprite.run(
        .repeatForever(
          .sequence([.moveBy(x: 6, y: 4, duration: 0.6), .moveBy(x: -6, y: -4, duration: 0.6)])))
    case .other:
      sprite.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 4)))
    case .mcp(let server, _):
      let color = NSColor(
        hue: Accent.hue(forProject: server), saturation: 0.45, brightness: 0.95, alpha: 1)
      if asset.tint == true {
        sprite.color = color
        sprite.colorBlendFactor = 1
      }
      if assetName == "prop_mcp_generic" {
        let tag = SKLabelNode(text: privacy ? "••" : Self.initials(server))
        tag.fontName = "AvenirNext-Bold"
        tag.fontSize = 14
        tag.fontColor = Palette.ink
        tag.verticalAlignmentMode = .center
        tag.zPosition = 2
        body.addChild(tag)
      }
      cable.lineWidth = 6
      cableCore.strokeColor = color
      cableCore.lineWidth = 3
      cableCore.zPosition = -0.5
      if let plugSprite = lib.sprite(ArtNames.mcpCable) {
        if lib.asset(ArtNames.mcpCable)?.tint == true {
          plugSprite.color = color
          plugSprite.colorBlendFactor = 1
        }
        plugSprite.zPosition = 1
        addChild(plugSprite)
        plug = plugSprite
      }
    default: break
    }
    return true
  }

  private func addSpinner(y: CGFloat) {
    let arc = SKShapeNode()
    let p = CGMutablePath()
    p.addArc(center: .zero, radius: 7, startAngle: 0, endAngle: .pi * 1.4, clockwise: false)
    arc.path = p
    arc.strokeColor = Palette.approval
    arc.lineWidth = 3
    arc.position = CGPoint(x: 0, y: y)
    arc.zPosition = 2
    arc.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 1)))
    body.addChild(arc)
  }

  /// The text under a prop (nil when there is none); redacted in privacy mode.
  func captionText(_ scene: ToolScene, privacy: Bool) -> String? {
    switch scene {
    case .read(let file): return name(file, privacy)
    case .search: return "search"
    case .edit(let file), .write(let file): return name(file, privacy)
    case .shell(let long, let background):
      return background ? "background" : (long ? "still running…" : "running")
    case .web: return "web"
    case .skill(let skill): return name(skill, privacy)
    case .mcp(let server, _): return name(server, privacy)
    case .todo: return "todo"
    case .plan: return "plan"
    case .subagent: return nil
    case .other(let tool): return name(tool, privacy)
    }
  }
}
