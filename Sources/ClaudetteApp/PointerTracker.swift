import AppKit

/// Reports the pointer position (global screen coordinates) for moves and drags, both over our
/// own overlay windows (local monitor) and everywhere else (global monitor).
final class PointerTracker {
  var onMove: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
  private var monitors: [Any] = []

  func start() {
    guard monitors.isEmpty else { return }
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]
    if let g = NSEvent.addGlobalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        self?.onMove?(NSEvent.mouseLocation, event.modifierFlags)
      })
    {
      monitors.append(g)
    }
    if let l = NSEvent.addLocalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        self?.onMove?(NSEvent.mouseLocation, event.modifierFlags)
        return event
      })
    {
      monitors.append(l)
    }
  }

  func stop() {
    monitors.forEach { NSEvent.removeMonitor($0) }
    monitors = []
  }

  deinit { stop() }
}
