import Foundation

/// One exported PNG. Points, SpriteKit space: origin bottom-left, y up.
public struct ArtAsset: Codable, Equatable, Sendable {
  public var file: String
  public var size: [Double]
  /// SpriteKit `anchorPoint`, each component 0...1.
  public var anchor: [Double]
  /// In the parent's space.
  public var position: [Double]?
  public var z: Double?
  public var parent: String?
  /// Set on texture variants (`eye_L.happy`): swaps the texture of the base asset's node.
  public var variantOf: String?
  /// Runtime-text slot in the asset's own space.
  public var label: [Double]?
  /// True for neutral grey art that is tinted at runtime (scarf, cartridge body).
  public var tint: Bool?

  public init(
    file: String, size: [Double], anchor: [Double], position: [Double]? = nil, z: Double? = nil,
    parent: String? = nil, variantOf: String? = nil, label: [Double]? = nil, tint: Bool? = nil
  ) {
    self.file = file
    self.size = size
    self.anchor = anchor
    self.position = position
    self.z = z
    self.parent = parent
    self.variantOf = variantOf
    self.label = label
    self.tint = tint
  }
}

public enum ArtManifestError: Error, Equatable {
  case unsupportedVersion(Int)
  case badScale(Int)
  case tooManyAssets(Int)
  case tooLarge(Int)
  case malformed
  case badFile(String)
  case badGeometry(String)
  case unknownParent(String)
  case parentCycle(String)
  case unknownVariantBase(String)
}

public struct ArtManifest: Codable, Equatable, Sendable {
  public static let supportedVersion = 1
  public static let maxBytes = 512 * 1024
  public static let maxAssets = 400
  public static let maxDimension = 2048.0
  /// Fixed parents besides other assets.
  public static let builtinParents: Set<String> = ["root", "bodyPivot", "face"]
  public static let requiredCharacter = [
    "shadow", "leg_0", "leg_1", "leg_2", "leg_3", "arm_L", "arm_R", "body", "blush_L", "blush_R",
    "eye_L", "eye_R", "mouth", "spark",
  ]

  public var version: Int
  public var scale: Int
  public var assets: [String: ArtAsset]

  public init(version: Int, scale: Int, assets: [String: ArtAsset]) {
    self.version = version
    self.scale = scale
    self.assets = assets
  }

  public static func decode(_ data: Data) throws -> ArtManifest {
    guard data.count <= maxBytes else { throw ArtManifestError.tooLarge(data.count) }
    guard let m = try? JSONDecoder().decode(ArtManifest.self, from: data) else {
      throw ArtManifestError.malformed
    }
    try m.validate()
    return m
  }

  public func hasCompleteCharacter() -> Bool {
    Self.requiredCharacter.allSatisfy { assets[$0] != nil }
  }

  public func validate() throws {
    guard version == Self.supportedVersion else {
      throw ArtManifestError.unsupportedVersion(version)
    }
    guard (1...4).contains(scale) else { throw ArtManifestError.badScale(scale) }
    guard assets.count <= Self.maxAssets else { throw ArtManifestError.tooManyAssets(assets.count) }
    // Sorted so the reported name is deterministic.
    for name in assets.keys.sorted() {
      let a = assets[name]!
      guard Self.isSafePNG(a.file) else { throw ArtManifestError.badFile(a.file) }
      guard Self.pair(a.size, in: 0...Self.maxDimension, exclusiveLow: true),
        Self.pair(a.anchor, in: 0...1)
      else { throw ArtManifestError.badGeometry(name) }
      if let p = a.position, !(p.count == 2 && p.allSatisfy(\.isFinite)) {
        throw ArtManifestError.badGeometry(name)
      }
      if let l = a.label, !(l.count == 2 && l.allSatisfy(\.isFinite)) {
        throw ArtManifestError.badGeometry(name)
      }
      if let z = a.z, !z.isFinite { throw ArtManifestError.badGeometry(name) }
      if let base = a.variantOf {
        guard let b = assets[base], b.variantOf == nil else {
          throw ArtManifestError.unknownVariantBase(name)
        }
      }
      if let parent = a.parent, !Self.builtinParents.contains(parent), assets[parent] == nil {
        throw ArtManifestError.unknownParent(name)
      }
    }
    for name in assets.keys.sorted() {
      var seen: Set<String> = [name]
      var cur = assets[name]?.parent
      while let p = cur, assets[p] != nil {
        guard seen.insert(p).inserted else { throw ArtManifestError.parentCycle(name) }
        cur = assets[p]?.parent
      }
    }
  }

  private static func isSafePNG(_ f: String) -> Bool {
    f.range(of: #"^[A-Za-z0-9_]+\.png$"#, options: .regularExpression) != nil
  }

  private static func pair(_ v: [Double], in range: ClosedRange<Double>, exclusiveLow: Bool = false)
    -> Bool
  {
    v.count == 2
      && v.allSatisfy {
        $0.isFinite && range.contains($0) && !(exclusiveLow && $0 == range.lowerBound)
      }
  }
}
