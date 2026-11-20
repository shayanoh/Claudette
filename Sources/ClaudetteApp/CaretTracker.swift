import AppKit
import ApplicationServices

/// Finds the text caret of whatever app has keyboard focus, through the Accessibility API (the
/// same source the Caps Lock and input-language tips use). Polls off the main thread: a hung app
/// must never stall the overlay. Needs Accessibility permission; without it nothing is reported.
final class CaretTracker {
  /// The caret's centre in global screen coordinates (bottom-left origin), or nil when there is none.
  var onCaret: ((CGPoint?) -> Void)?
  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "claudette.caret", qos: .utility)

  /// Shows the system Accessibility prompt if access has not been granted yet.
  static func requestAccess() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func start() {
    guard timer == nil else { return }
    let t = DispatchSource.makeTimerSource(queue: queue)
    t.schedule(deadline: .now(), repeating: .milliseconds(200))
    t.setEventHandler { [weak self] in
      let p = Self.caret()
      DispatchQueue.main.async { self?.onCaret?(p) }
    }
    t.resume()
    timer = t
  }

  func stop() {
    timer?.cancel()
    timer = nil
  }

  private static func caret() -> CGPoint? {
    guard AXIsProcessTrusted() else { return nil }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.15)
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    let element = focused as! AXUIElement  // type checked just above
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
    AXUIElementSetMessagingTimeout(element, 0.15)

    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        == .success, let value, CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else {
      return nil
    }
    let end = range.location + range.length
    // Many apps return an empty rect for an empty range: fall back to the character after the
    // caret, then the one before it.
    for (location, length) in [(end, 0), (end, 1), (end - 1, 1)] where location >= 0 {
      if let rect = bounds(element, CFRange(location: location, length: length)) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let x = length == 1 && location == end - 1 ? rect.maxX : rect.minX
        return CGPoint(x: x, y: screenHeight - rect.midY)  // AX is top-left origin
      }
    }
    return nil
  }

  private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
    var r = range
    guard let arg = AXValueCreate(.cfRange, &r) else { return nil }
    var out: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXBoundsForRangeParameterizedAttribute as CFString, arg, &out) == .success,
      let out, CFGetTypeID(out) == AXValueGetTypeID()
    else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.height > 0, rect.height < 400,
      rect.origin.x.isFinite, rect.origin.y.isFinite
    else { return nil }
    return rect
  }
}
