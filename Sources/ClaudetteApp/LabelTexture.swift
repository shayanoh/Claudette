import AppKit
import SpriteKit

/// White item labels with one soft blurred shadow, drawn once per (text, size) and cached:
/// no live effect node, so resting labels cost nothing per frame.
enum LabelTexture {
  /// Transparent border that keeps the blurred shadow from being clipped.
  static let padding: CGFloat = 8

  struct Entry {
    let texture: SKTexture
    /// Size in points, including `padding` on every side.
    let size: CGSize
  }

  private final class Box {
    let entry: Entry
    init(_ entry: Entry) { self.entry = entry }
  }

  private static let cache: NSCache<NSString, Box> = {
    let c = NSCache<NSString, Box>()
    c.countLimit = 300
    return c
  }()

  static func entry(_ text: String, size: CGFloat, mono: Bool = false) -> Entry? {
    guard !text.isEmpty, size.isFinite, size > 1 else { return nil }
    let key = "\(mono ? "m" : "p")\(size)|\(text)" as NSString
    if let hit = cache.object(forKey: key) { return hit.entry }
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -1.5)
    shadow.shadowBlurRadius = 4
    shadow.shadowColor = Palette.ink.withAlphaComponent(0.85)
    let font =
      mono
      ? NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
      : (NSFont(name: "AvenirNext-DemiBold", size: size) ?? .boldSystemFont(ofSize: size))
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: NSColor.white, .shadow: shadow,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let text = string.size()
    let total = NSSize(
      width: ceil(text.width) + padding * 2, height: ceil(text.height) + padding * 2)
    let image = NSImage(size: total, flipped: false) { _ in
      // Twice: stacks the blurred shadow so it holds up on light wallpapers.
      string.draw(at: NSPoint(x: padding, y: padding))
      string.draw(at: NSPoint(x: padding, y: padding))
      return true
    }
    let entry = Entry(texture: SKTexture(image: image), size: total)
    cache.setObject(Box(entry), forKey: key)
    return entry
  }
}
