import AppKit
import ClaudetteCore
import SpriteKit

/// `--render-props`: every prop kind on a light and a dark backdrop, to judge label legibility
/// without arranging a live scene.
enum PropSheet {
  static func render(to url: URL) -> Bool {
    let scenes: [ToolScene] = [
      .read(file: "auth.ts"), .edit(file: "LoginViewController.swift"),
      .shell(long: false, background: false),
      .mcp(server: "github", tool: "create_issue"), .skill(name: "superpowers:brainstorming"),
    ]
    let size = CGSize(width: 140 * CGFloat(scenes.count), height: 220)
    let scene = SKScene(size: CGSize(width: size.width, height: size.height * 2))
    scene.anchorPoint = .zero
    scene.backgroundColor = .clear
    for (row, color) in [NSColor.white, NSColor(white: 0.12, alpha: 1)].enumerated() {
      let backdrop = SKSpriteNode(color: color, size: size)
      backdrop.anchorPoint = .zero
      backdrop.position = CGPoint(x: 0, y: CGFloat(row) * size.height)
      scene.addChild(backdrop)
      for (i, s) in scenes.enumerated() {
        let node = PropNode(scene: s, privacy: false)
        node.position = CGPoint(x: 70 + 140 * CGFloat(i), y: CGFloat(row) * size.height + 130)
        scene.addChild(node)
      }
    }
    let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
    guard let texture = view.texture(from: scene) else { return false }
    let rep = NSBitmapImageRep(cgImage: texture.cgImage())
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    do {
      try png.write(to: url)
      return true
    } catch {
      return false
    }
  }
}
