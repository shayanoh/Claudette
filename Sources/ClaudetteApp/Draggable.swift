import AppKit

/// Something on the overlay, besides the avatars, that the pointer can hover and drag: the weekly
/// moon now, items later. Coordinates are global screen coordinates (origin bottom-left).
protocol Draggable: AnyObject {
  /// Where the pointer is captured; `.null` while hidden.
  var hitRect: CGRect { get }
  func pointerEntered()
  func pointerExited()
  func dragBegan(at point: CGPoint)
  func dragMoved(to point: CGPoint)
  func dragEnded(at point: CGPoint)
}
