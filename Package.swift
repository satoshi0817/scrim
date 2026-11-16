// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sheerpane",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SheerpaneCore", targets: ["SheerpaneCore"]),
        .executable(name: "Sheerpane", targets: ["Sheerpane"]),
    ],
    targets: [
        .target(name: "SheerpaneCore"),
        .target(name: "SheerpaneAssets", resources: [.process("Resources")]),
        .executableTarget(name: "Sheerpane", dependencies: ["SheerpaneCore", "SheerpaneAssets"]),
        .testTarget(name: "SheerpaneTests", dependencies: ["SheerpaneCore", "SheerpaneAssets"]),
    ]
)
