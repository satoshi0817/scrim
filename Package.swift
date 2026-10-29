// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Chira",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChiraCore", targets: ["ChiraCore"]),
        .executable(name: "Chira", targets: ["Chira"]),
    ],
    targets: [
        .target(name: "ChiraCore"),
        .executableTarget(name: "Chira", dependencies: ["ChiraCore"]),
        .testTarget(name: "ChiraTests", dependencies: ["ChiraCore"]),
    ]
)
