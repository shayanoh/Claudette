import ClaudetteCore
import Foundation
import ImageIO
import SpriteKit

/// The loaded art export (manifest + PNG textures). `shared` is nil when the export is missing or
/// invalid, or `CLAUDETTE_DEBUG_ART=off`; callers then use the shape placeholders.
final class ArtLibrary {
  static let shared: ArtLibrary? = locate()

  let manifest: ArtManifest
  let directory: URL
  private var cache: [String: SKTexture] = [:]
  private var failed: Set<String> = []

  var scale: Int { manifest.scale }

  /// Succeeds only if the manifest is valid and every required character PNG loads, so the
  /// puppet is built from art entirely or not at all.
  init?(directory: URL) {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
      let m = try? ArtManifest.decode(data), m.hasCompleteCharacter()
    else { return nil }
    manifest = m
    self.directory = directory
    for name in ArtManifest.requiredCharacter where texture(name) == nil {
      NSLog("Claudette: art asset \(name) cannot be loaded; using placeholder art")
      return nil
    }
  }

  func asset(_ name: String) -> ArtAsset? { manifest.assets[name] }

  /// The texture for `name`, or nil when the asset is unknown or its PNG is unreadable.
  func texture(_ name: String) -> SKTexture? {
    if let t = cache[name] { return t }
    guard !failed.contains(name), let a = manifest.assets[name] else { return nil }
    let url = directory.appendingPathComponent(a.file)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else {
      failed.insert(name)
      return nil
    }
    let t = SKTexture(cgImage: image)
    t.filteringMode = .linear
    cache[name] = t
    return t
  }

  /// A sprite for `name` sized, anchored, positioned and ordered per the manifest.
  func sprite(_ name: String) -> SKSpriteNode? {
    guard let a = asset(name), let t = texture(name) else { return nil }
    let n = SKSpriteNode(texture: t, size: CGSize(width: a.size[0], height: a.size[1]))
    n.anchorPoint = CGPoint(x: a.anchor[0], y: a.anchor[1])
    if let p = a.position { n.position = CGPoint(x: p[0], y: p[1]) }
    n.zPosition = CGFloat(a.z ?? 0)
    n.name = name
    return n
  }

  private static func locate(
    env: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main
  ) -> ArtLibrary? {
    if env["CLAUDETTE_DEBUG_ART"] == "off" { return nil }
    var dirs: [URL] = []
    if let p = env["CLAUDETTE_ART"], !p.isEmpty { dirs.append(URL(fileURLWithPath: p)) }
    if let r = bundle.resourceURL { dirs.append(r.appendingPathComponent("art")) }
    dirs.append(URL(fileURLWithPath: "art/export"))
    for dir in dirs {
      guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path)
      else { continue }
      if let lib = ArtLibrary(directory: dir) { return lib }
      NSLog("Claudette: art at \(dir.path) is invalid; using placeholder art")
      return nil
    }
    return nil
  }
}
