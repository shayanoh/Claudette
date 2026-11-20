import Foundation
import Testing

@testable import ClaudetteCore

private func asset(
  _ file: String = "a.png", size: [Double] = [10, 10], anchor: [Double] = [0.5, 0.5],
  parent: String? = "root", variantOf: String? = nil
) -> ArtAsset {
  ArtAsset(
    file: file, size: size, anchor: anchor, position: variantOf == nil ? [0, 0] : nil, z: nil,
    parent: variantOf == nil ? parent : nil, variantOf: variantOf, label: nil, tint: nil)
}

private func manifest(_ assets: [String: ArtAsset], version: Int = 1, scale: Int = 2)
  -> ArtManifest
{
  ArtManifest(version: version, scale: scale, assets: assets)
}

private func complete() -> ArtManifest {
  var a: [String: ArtAsset] = [:]
  for n in ArtManifest.requiredCharacter { a[n] = asset("\(n).png") }
  return manifest(a)
}

@Test func validManifestDecodes() throws {
  let data = try JSONEncoder().encode(complete())
  let m = try ArtManifest.decode(data)
  #expect(m.hasCompleteCharacter())
  #expect(m.scale == 2)
}

@Test func rejectsVersion2() {
  #expect(throws: ArtManifestError.unsupportedVersion(2)) {
    try manifest([:], version: 2).validate()
  }
}

@Test func rejectsTraversalAndBadFiles() {
  for bad in ["../x.png", "a/b.png", "x.jpg", "/abs.png", ""] {
    #expect(throws: ArtManifestError.badFile(bad)) {
      try manifest(["p": asset(bad)]).validate()
    }
  }
}

@Test func rejectsNaNAndOutOfRangeGeometry() {
  for a in [
    asset(size: [.nan, 10]), asset(size: [0, 10]), asset(size: [5000, 10]),
    asset(anchor: [1.5, 0]), asset(anchor: [.nan, 0]), asset(anchor: [0.5]),
  ] {
    #expect(throws: ArtManifestError.badGeometry("p")) {
      try manifest(["p": a]).validate()
    }
  }
}

@Test func rejectsParentCycleAndUnknownParent() {
  #expect(throws: ArtManifestError.parentCycle("a")) {
    try manifest(["a": asset(parent: "b"), "b": asset(parent: "a")]).validate()
  }
  #expect(throws: ArtManifestError.unknownParent("a")) {
    try manifest(["a": asset(parent: "nope")]).validate()
  }
}

@Test func variantNeedsExistingBase() {
  #expect(throws: ArtManifestError.unknownVariantBase("eye_L.happy")) {
    try manifest(["eye_L.happy": asset(variantOf: "eye_L")]).validate()
  }
}

@Test func rejectsOversizedData() {
  #expect(throws: ArtManifestError.self) {
    _ = try ArtManifest.decode(Data(count: 600 * 1024))
  }
}

@Test func incompleteCharacterIsDetected() throws {
  var m = complete()
  m.assets["spark"] = nil
  try m.validate()
  #expect(!m.hasCompleteCharacter())
}
