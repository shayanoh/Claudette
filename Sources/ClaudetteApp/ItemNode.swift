import AppKit
import ClaudetteCore
import SpriteKit

/// One item lying on the screen (a file, a terminal, a tool). It belongs to the stage, not to any
/// Claudette: they walk to it, and the mouse can pick it up and move it.
final class ItemNode: SKNode, Draggable {
  let itemID: ItemID
  private(set) var display: CGDirectDisplayID
  private var prop: PropNode
  private let privacy: Bool
  private let isTerminal: Bool
  /// Hover text: the full command, a path, and for a finished terminal its result.
  var tooltipLines: () -> [String] = { [] }
  /// Global origin (lower-left) of a display, to turn scene coordinates into screen coordinates.
  var originOfDisplay: (CGDirectDisplayID) -> CGPoint = { _ in .zero }
  var onDropped: ((ItemNode, CGPoint) -> Void)?
  private var grab = CGPoint.zero
  private var isDragging = false
  private var tip: SKNode?

  static let footprint = CGSize(width: 64, height: 80)

  init(id: ItemID, scene: ToolScene, display: CGDirectDisplayID, privacy: Bool, uiScale: CGFloat) {
    itemID = id
    self.display = display
    self.privacy = privacy
    if case .shell = scene { isTerminal = true } else { isTerminal = false }
    prop = PropNode(scene: scene, privacy: privacy)
    super.init()
    addChild(prop)
    prop.plug?.isHidden = true  // the MCP cable is gone: items are not tied to anyone
    setUIScale(uiScale)
  }

  required init?(coder: NSCoder) { fatalError("not supported") }

  private var typeFactor: CGFloat { isTerminal ? 1.3 : 1 }
  private var uiScale: CGFloat = 1

  func setUIScale(_ s: CGFloat) {
    uiScale = s
    setScale(s * typeFactor)
  }

  /// In her hands the item is a child of her puppet (which already carries the size setting).
  func setHeld(_ held: Bool) { setScale(held ? 0.8 * typeFactor : uiScale * typeFactor) }

  /// Terminals get bigger and show the start of the command on their screen.
  func showCommand(_ command: String) {
    prop.body.childNode(withName: "command")?.removeFromParent()
    guard isTerminal, !command.isEmpty else { return }
    let size: CGFloat = 6.5
    // About 26 pt of screen is free right of the prompt glyph; monospaced glyphs are ~0.6 em wide.
    let fit = max(1, Int(26 / (size * 0.6)))
    let text =
      privacy ? "•••" : (command.count > fit ? String(command.prefix(fit - 1)) + "…" : command)
    guard let entry = LabelTexture.entry(text, size: size, mono: true) else { return }
    let sprite = SKSpriteNode(texture: entry.texture, size: entry.size)
    sprite.name = "command"
    sprite.anchorPoint = CGPoint(x: 0, y: 0.5)
    // The texture carries `LabelTexture.padding` of shadow room on its left: start the glyphs at -6.
    sprite.position = CGPoint(x: -6 - LabelTexture.padding, y: 1)
    sprite.zPosition = 3
    prop.body.addChild(sprite)
  }

  /// Rebuilds the prop (a terminal turning into "still running…", then "done" or "failed").
  func restyle(_ scene: ToolScene, caption: String? = nil, command: String? = nil) {
    prop.removeFromParent()
    prop = PropNode(scene: scene, privacy: privacy, caption: caption)
    prop.plug?.isHidden = true
    addChild(prop)
    if let command { showCommand(command) }
  }

  /// Appears with a small pop at its final size.
  func popIn() {
    let final = xScale
    setScale(0.01)
    run(.scale(to: final, duration: 0.25))
  }

  func pop() {
    run(.sequence([.scale(by: 1.15, duration: 0.08), .scale(by: 1 / 1.15, duration: 0.12)]))
  }

  func moveToDisplay(_ id: CGDirectDisplayID) { display = id }

  // MARK: Draggable

  var globalCenter: CGPoint {
    let o = originOfDisplay(display)
    return CGPoint(x: position.x + o.x, y: position.y + o.y)
  }

  var hitRect: CGRect {
    guard parent != nil, !isHidden else { return .null }
    let w = Self.footprint.width * xScale
    let h = Self.footprint.height * yScale
    let c = globalCenter
    return CGRect(x: c.x - w / 2, y: c.y - h / 2 - 6 * yScale, width: w, height: h)
  }

  func pointerEntered() {
    guard tip == nil, !isDragging else { return }
    let lines = tooltipLines().filter { !$0.isEmpty }
    guard !lines.isEmpty else { return }
    let node = SKNode()
    var y: CGFloat = 0
    var width: CGFloat = 0
    var sprites: [(SKSpriteNode, CGFloat)] = []
    for line in lines.reversed() {
      guard let e = LabelTexture.entry(String(line.prefix(120)), size: 11) else { continue }
      let s = SKSpriteNode(texture: e.texture, size: e.size)
      sprites.append((s, y))
      width = max(width, e.size.width)
      y += e.size.height - 8
    }
    let pill = SKShapeNode(
      rect: CGRect(x: -width / 2, y: -4, width: width, height: y + 6), cornerRadius: 8)
    pill.fillColor = Palette.ink.withAlphaComponent(0.88)
    pill.strokeColor = .clear
    node.addChild(pill)
    for (s, sy) in sprites {
      s.anchorPoint = CGPoint(x: 0.5, y: 0)
      s.position = CGPoint(x: 0, y: sy - 4)
      s.zPosition = 1
      node.addChild(s)
    }
    node.position = CGPoint(x: 0, y: 48)
    node.zPosition = 100
    zPosition = Stage.overlayZ - 10  // its tooltip must not hide behind a Claudette
    node.setScale(1 / max(xScale, 0.01))  // readable at any size setting
    node.alpha = 0
    addChild(node)
    node.run(.fadeIn(withDuration: 0.1))
    tip = node
  }

  func pointerExited() {
    if tip != nil, !isDragging { zPosition = 0 }
    tip?.removeFromParent()
    tip = nil
  }

  func dragBegan(at point: CGPoint) {
    pointerExited()
    isDragging = true
    removeAllActions()
    zPosition = Stage.overlayZ - 5
    let c = globalCenter
    grab = CGPoint(x: c.x - point.x, y: c.y - point.y)
    run(.scale(by: 1.12, duration: 0.08))
  }

  func dragMoved(to point: CGPoint) {
    guard isDragging else { return }
    let o = originOfDisplay(display)
    position = CGPoint(x: point.x + grab.x - o.x, y: point.y + grab.y - o.y)
  }

  func dragEnded(at point: CGPoint) {
    guard isDragging else { return }
    isDragging = false
    zPosition = 0
    run(.scale(by: 1 / 1.12, duration: 0.1))
    onDropped?(self, globalCenter)
  }
}
