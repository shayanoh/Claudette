import CoreGraphics
import Foundation

/// Where Claudettes and items may be: the screen minus the menu bar, the Dock and room for the Dock
/// to grow when its magnification is on.
public enum WalkArea {
  /// `visible` is `NSScreen.visibleFrame` (already clear of the menu bar and a Dock that is shown
  /// and locked). The Dock's side is the one where `visible` is inset from `screen` (at the bottom,
  /// left or right); that side loses `magnifiedExtra` more. An auto-hiding Dock leaves no inset, so
  /// nothing is reserved. The result never gets smaller than 40% of the screen.
  public static func frame(screen: CGRect, visible: CGRect, magnifiedExtra: CGFloat) -> CGRect {
    guard magnifiedExtra.isFinite, magnifiedExtra > 0 else { return visible }
    let extra = min(magnifiedExtra, 400)
    var r = visible
    if visible.minY - screen.minY > 1 {
      r.origin.y += extra
      r.size.height -= extra
    } else if visible.minX - screen.minX > 1 {
      r.origin.x += extra
      r.size.width -= extra
    } else if screen.maxX - visible.maxX > 1 {
      r.size.width -= extra
    }
    guard r.width >= screen.width * 0.4, r.height >= screen.height * 0.4 else { return visible }
    return r
  }
}
