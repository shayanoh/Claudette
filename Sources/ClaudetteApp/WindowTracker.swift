import AppKit
import ClaudetteCore

/// Reads where other apps' windows are, from the window server. Only bounds, layer and owner are
/// used (titles would need Screen Recording permission, and are never read).
enum WindowTracker {
  /// On-screen windows, front to back, in the stage's coordinates (origin bottom-left).
  static func poll() -> [WindowFrame] {
    guard
      let info = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]],
      let primary = NSScreen.screens.first
    else { return [] }
    var out: [WindowFrame] = []
    for w in info {
      guard let number = w[kCGWindowNumber as String] as? Int,
        let layer = w[kCGWindowLayer as String] as? Int,
        let pid = w[kCGWindowOwnerPID as String] as? Int32,
        let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDict),
        (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05
      else { continue }
      // Quartz has its origin at the top-left of the primary display; the stage at the bottom-left.
      let frame = CGRect(
        x: bounds.minX, y: primary.frame.height - bounds.maxY, width: bounds.width,
        height: bounds.height)
      out.append(WindowFrame(number: number, frame: frame, layer: layer, ownerPID: pid))
    }
    return out
  }
}
