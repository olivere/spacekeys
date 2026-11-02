// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spacekeys",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "SpaceKeysCore"),
        .executableTarget(name: "SpaceKeys", dependencies: ["SpaceKeysCore"]),
        .testTarget(name: "SpaceKeysCoreTests", dependencies: ["SpaceKeysCore"]),
    ]
)
