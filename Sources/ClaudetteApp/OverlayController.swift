import AppKit
import SpriteKit

/// A borderless, transparent, click-through panel that never takes focus.
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// One overlay panel (hosting one SpriteKit scene) per display, visible on every Space and over
/// full-screen apps.
final class OverlayController {
  struct Overlay {
    let panel: OverlayPanel
    let view: SKView
    let scene: SKScene
  }

  private(set) var overlays: [CGDirectDisplayID: Overlay] = [:]
  var onScreensChanged: (() -> Void)?

  init() {
    rebuild()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }

  var mainScene: SKScene? {
    if let main = NSScreen.main, let id = Self.displayID(of: main), let o = overlays[id] {
      return o.scene
    }
    return overlays.values.first?.scene
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
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false

    let view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
    view.allowsTransparency = true
    view.preferredFramesPerSecond = 30
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
