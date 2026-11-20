import AppKit
import SpriteKit

enum MousePhase { case down, dragged, up }

/// A borderless, transparent, click-through panel that never takes focus.
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Forwards clicks and drags (as global screen coordinates) to the stage.
final class StageView: SKView {
  var handler: ((MousePhase, CGPoint) -> Void)?
  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { handler?(.down, NSEvent.mouseLocation) }
  override func mouseDragged(with event: NSEvent) { handler?(.dragged, NSEvent.mouseLocation) }
  override func mouseUp(with event: NSEvent) { handler?(.up, NSEvent.mouseLocation) }
}

/// One overlay panel (hosting one SpriteKit scene) per display, visible on every Space and over
/// full-screen apps.
final class OverlayController {
  struct Overlay {
    let panel: OverlayPanel
    let view: StageView
    let scene: SKScene
  }

  private(set) var overlays: [CGDirectDisplayID: Overlay] = [:]
  var onScreensChanged: (() -> Void)?
  var mouseHandler: ((MousePhase, CGPoint) -> Void)? {
    didSet { overlays.values.forEach { $0.view.handler = mouseHandler } }
  }

  init() {
    rebuild()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }

  var mainDisplayID: CGDirectDisplayID? {
    if let main = NSScreen.main, let id = Self.displayID(of: main), overlays[id] != nil {
      return id
    }
    return overlays.keys.sorted().first
  }

  /// Focus mode hides every overlay (and stops rendering) without losing any state.
  var focusHidden = false {
    didSet {
      guard focusHidden != oldValue else { return }
      for o in overlays.values {
        if focusHidden { o.panel.orderOut(nil) } else { o.panel.orderFrontRegardless() }
        o.view.isPaused = focusHidden || paused
      }
    }
  }
  private var paused = false

  /// Idle scenes only breathe and blink, so they run slowly; anything lively asks for full speed.
  func setFrameRate(_ fps: Int) {
    overlays.values.forEach { $0.view.preferredFramesPerSecond = fps }
  }

  /// Pauses rendering when there is nothing to draw.
  func setPaused(_ paused: Bool) {
    self.paused = paused
    overlays.values.forEach { $0.view.isPaused = paused || focusHidden }
  }

  @objc private func screensChanged() {
    rebuild()
    onScreensChanged?()
  }

  /// Creates panels for new displays, resizes existing ones, and drops those that went away.
  func rebuild() {
    var seen = Set<CGDirectDisplayID>()
    for screen in NSScreen.screens {
      guard let id = Self.displayID(of: screen) else { continue }
      seen.insert(id)
      if let existing = overlays[id] {
        existing.panel.setFrame(screen.frame, display: true)
        existing.scene.size = screen.frame.size
      } else {
        overlays[id] = makeOverlay(for: screen)
      }
    }
    for id in overlays.keys where !seen.contains(id) {
      overlays[id]?.panel.orderOut(nil)
      overlays[id] = nil
    }
  }

  private func makeOverlay(for screen: NSScreen) -> Overlay {
    let panel = OverlayPanel(
      contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true  // switched off only while the pointer is over a sprite
    panel.acceptsMouseMovedEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false

    let view = StageView(frame: CGRect(origin: .zero, size: screen.frame.size))
    view.handler = mouseHandler
    view.allowsTransparency = true
    view.preferredFramesPerSecond = Stage.activeFPS
    view.ignoresSiblingOrder = true
    let scene = SKScene(size: screen.frame.size)
    scene.backgroundColor = .clear
    scene.scaleMode = .resizeFill
    view.presentScene(scene)
    panel.contentView = view
    panel.orderFrontRegardless()
    return Overlay(panel: panel, view: view, scene: scene)
  }
}
