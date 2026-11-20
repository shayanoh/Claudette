import ClaudetteCore
import Foundation
import ImageIO

/// `Claudette --validate-art <dir>`: manifest is valid, the character is complete, and every PNG
/// exists with the pixel size the manifest promises (size * scale).
enum ArtCheck {
  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  static func validate(dir: URL) throws -> Int {
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else {
      throw Failure(description: "cannot read manifest.json in \(dir.path)")
    }
    let manifest = try ArtManifest.decode(data)
    guard manifest.hasCompleteCharacter() else {
      let missing = ArtManifest.requiredCharacter.filter { manifest.assets[$0] == nil }
      throw Failure(
        description: "character incomplete, missing: \(missing.joined(separator: ", "))")
    }
    for (name, a) in manifest.assets.sorted(by: { $0.key < $1.key }) {
      let url = dir.appendingPathComponent(a.file)
      guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
        let w = props[kCGImagePropertyPixelWidth] as? Int,
        let h = props[kCGImagePropertyPixelHeight] as? Int
      else { throw Failure(description: "\(name): \(a.file) missing or not a readable PNG") }
      let ew = Int((a.size[0] * Double(manifest.scale)).rounded())
      let eh = Int((a.size[1] * Double(manifest.scale)).rounded())
      guard w == ew, h == eh else {
        throw Failure(description: "\(name): \(a.file) is \(w)x\(h) px, manifest says \(ew)x\(eh)")
      }
    }
    return manifest.assets.count
  }
}
