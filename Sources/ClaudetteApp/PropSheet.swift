import AppKit
import ClaudetteCore
import SpriteKit
import SwiftUI

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
      // Terminal items (1.3x, the start of the command on the screen): running, then done.
      for (i, caption) in [nil, "done"].enumerated() {
        let item = ItemNode(
          id: ItemID.tool(useID: "t\(i)"), scene: .shell(long: false, background: false),
          display: 0, privacy: false, uiScale: 1)
        item.restyle(
          .shell(long: false, background: false), caption: caption, command: "npm run build --watch"
        )
        item.position = CGPoint(x: 70 + 140 * CGFloat(i), y: CGFloat(row) * size.height + 50)
        scene.addChild(item)
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

extension PropSheet {
  /// Two overlapping Claudettes drawn like the overlay does (`ignoresSiblingOrder`): left with the
  /// same z (parts interleave), right with a z band each (the one in front is whole).
  static func renderOverlap(to url: URL) -> Bool {
    let scene = SKScene(size: CGSize(width: 1340, height: 300))
    scene.anchorPoint = .zero
    scene.backgroundColor = NSColor(white: 0.9, alpha: 1)
    for (half, zs) in [(0, (0.0, 0.0)), (1, (200.0, 400.0))] {
      for (i, hue) in [0.08, 0.55].enumerated() {
        let puppet = PuppetNode()
        puppet.setScale(0.8)
        puppet.setAccent(hue: hue)
        puppet.position = CGPoint(x: 120 + CGFloat(half) * 380 + CGFloat(i) * 110, y: 30)
        puppet.zPosition = CGFloat(i == 0 ? zs.0 : zs.1)
        scene.addChild(puppet)
      }
    }
    // Thinking bubble and a small sub-agent.
    let thinker = PuppetNode()
    thinker.setScale(0.8)
    thinker.position = CGPoint(x: 800, y: 50)
    thinker.zPosition = 200
    thinker.think(true)
    scene.addChild(thinker)
    let sub = PuppetNode()
    sub.setScale(0.8 * 0.55)
    sub.position = CGPoint(x: 940, y: 50)
    sub.zPosition = 300
    sub.setAccent(hue: 0.3)
    scene.addChild(sub)
    for (i, angle) in [0.0, -1.0].enumerated() {  // the trash can, lid closed and open
      let can = TrashCanNode()
      can.setLidAngle(CGFloat(angle))
      can.position = CGPoint(x: 1090 + CGFloat(i) * 120, y: 50)
      scene.addChild(can)
    }
    let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
    view.ignoresSiblingOrder = true
    view.presentScene(scene)
    guard let texture = view.texture(from: scene) else { return false }
    let rep = NSBitmapImageRep(cgImage: texture.cgImage())
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
  }
}

extension PropSheet {
  /// One Claudette per animation beat, frozen right after it starts (arm and eye variants show).
  static func renderPoses(to url: URL) -> Bool {
    let beats: [(String, (PuppetNode) -> Void)] = [
      (
        "carry",
        {
          $0.carrying = true
          $0.restoreArms()
        }
      ),
      ("typing", { $0.perform(.typing) }),
      ("read", { $0.perform(.read) }),
      ("shrug", { $0.perform(.shrug) }),
      ("celebrate", { $0.perform(.celebrate) }),
      ("startled", { $0.perform(.startled) }),
      ("yawn", { $0.perform(.yawn) }),
      ("stretch", { $0.perform(.stretch) }),
    ]
    let scene = SKScene(size: CGSize(width: 260 * CGFloat(beats.count), height: 330))
    scene.anchorPoint = .zero
    scene.backgroundColor = NSColor(white: 0.9, alpha: 1)
    for (i, beat) in beats.enumerated() {
      let puppet = PuppetNode()
      puppet.reduceMotion = true  // textures only: nothing is mid-motion in a still
      puppet.setScale(0.8)
      puppet.position = CGPoint(x: 130 + 260 * CGFloat(i), y: 40)
      scene.addChild(puppet)
      beat.1(puppet)
      guard let tag = LabelTexture.entry(beat.0, size: 14) else { continue }
      let label = SKSpriteNode(texture: tag.texture, size: tag.size)
      label.colorBlendFactor = 1
      label.position = CGPoint(x: 130 + 260 * CGFloat(i), y: 300)
      scene.addChild(label)
    }
    let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
    view.presentScene(scene)
    guard let texture = view.texture(from: scene) else { return false }
    let rep = NSBitmapImageRep(cgImage: texture.cgImage())
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
  }
}

extension PropSheet {
  private static func sampleItem() -> Item {
    var w = WorldModel()
    let command =
      "swift build --configuration release --product Claudette && codesign --force --sign - --deep build/Claudette.app && ditto -c -k --keepParent build/Claudette.app build/Claudette.zip && shasum -a 256 build/Claudette.zip | tee build/Claudette.sha256 && echo finished packaging the release for distribution on this machine only"
    let t = ToolActivity(
      toolUseID: "t1", toolName: "Bash",
      input: .object(["command": .string(command), "description": .string("Package a release")]),
      startedAt: Date())
    _ = w.touch(
      for: "5e3a91c2-aaaa-bbbb-cccc-0123456789ab", tool: t,
      scene: .shell(long: false, background: false), cwd: "/Users/me/programming/Claudette",
      now: Date())
    w.finish(
      toolUseID: "t1",
      result: ToolResult(success: true, durationMs: 15286, summary: "Compiling…\nBuild complete!"))
    return w.all[0]
  }

  /// A terminal item with its hover text open (left) and its detail window content (right).
  static func renderHover(to url: URL) -> Bool {
    let item = sampleItem()
    let scene = SKScene(size: CGSize(width: 1100, height: 330))
    scene.anchorPoint = .zero
    scene.backgroundColor = NSColor(white: 0.25, alpha: 1)
    let node = ItemNode(
      id: item.id, scene: .shell(long: false, background: false), display: 0, privacy: false,
      uiScale: 1)
    node.restyle(
      .shell(long: false, background: false), caption: "done", command: item.terminal?.command)
    node.tooltipLines = { ItemDetails.hover(item) }
    node.position = CGPoint(x: 260, y: 90)
    scene.addChild(node)
    node.pointerEntered()
    node.removeAllActions()
    for child in node.children where child.alpha < 1 { child.alpha = 1 }
    let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
    view.presentScene(scene)
    guard let texture = view.texture(from: scene) else { return false }
    let left = NSBitmapImageRep(cgImage: texture.cgImage())

    let host = NSHostingView(
      rootView: ItemDetailView(
        title: item.label, rows: ItemDetails.rows(item), command: item.terminal?.command))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = CGRect(x: 0, y: 0, width: 560, height: 420)
    host.layoutSubtreeIfNeeded()
    guard let right = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
    host.cacheDisplay(in: host.bounds, to: right)

    let out = NSImage(size: NSSize(width: 1100 + 580, height: 420))
    out.lockFocus()
    NSColor.windowBackgroundColor.setFill()
    NSRect(x: 0, y: 0, width: 1680, height: 420).fill()
    left.draw(in: NSRect(x: 0, y: 45, width: 1100, height: 330))
    right.draw(in: NSRect(x: 1110, y: 0, width: 560, height: 420))
    out.unlockFocus()
    guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
    else { return false }
    return (try? png.write(to: url)) != nil
  }
}
