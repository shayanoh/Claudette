// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Claudette",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudetteCore", targets: ["ClaudetteCore"]),
        .executable(name: "ClaudetteApp", targets: ["ClaudetteApp"]),
    ],
    targets: [
        .target(name: "ClaudetteCore"),
        .executableTarget(name: "ClaudetteApp", dependencies: ["ClaudetteCore"]),
        .testTarget(name: "ClaudetteCoreTests", dependencies: ["ClaudetteCore"]),
    ],
    swiftLanguageModes: [.v5]
)
