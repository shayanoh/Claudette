import AppKit
import ClaudetteCore

/// What the Dock needs beyond `NSScreen.visibleFrame`: room to grow when magnification is on.
/// (`visibleFrame` already excludes a Dock that is shown and locked, and ignores an auto-hiding one.)
enum DockInfo {
  private static var cached: (at: Date, extra: CGFloat)?

  static var magnifiedExtra: CGFloat {
    if let c = cached, Date().timeIntervalSince(c.at) < 5 { return c.extra }
    let extra = read()
    cached = (Date(), extra)
    return extra
  }

  static func invalidate() { cached = nil }

  private static func read() -> CGFloat {
    func value(_ key: String) -> Any? {
      CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString)
    }
    guard (value("magnification") as? Bool) == true else { return 0 }
    let tile = (value("tilesize") as? Double) ?? 48
    let large = (value("largesize") as? Double) ?? 128
    guard tile.isFinite, large.isFinite else { return 0 }
    // A magnified Dock is a little taller than the magnified tile itself.
    return CGFloat(max(0, large - tile) * 1.1)
  }
}
