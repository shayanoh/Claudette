import Testing

@testable import ClaudetteCore

@Test func versionIsSemver() {
  let parts = ClaudetteCore.version.split(separator: ".")
  #expect(parts.count == 3)
  #expect(parts.allSatisfy { Int($0) != nil })
}
