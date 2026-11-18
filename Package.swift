// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlanceBar",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "GlanceBar", targets: ["GlanceBar"]),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "GlanceBar", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
