// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Scrim",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScrimCore", targets: ["ScrimCore"]),
        .executable(name: "Scrim", targets: ["Scrim"]),
    ],
    targets: [
        .target(name: "ScrimCore"),
        .target(name: "ScrimAssets", resources: [.process("Resources")]),
        .executableTarget(name: "Scrim", dependencies: ["ScrimCore", "ScrimAssets"]),
        .testTarget(name: "ScrimTests", dependencies: ["ScrimCore", "ScrimAssets"]),
    ]
)
