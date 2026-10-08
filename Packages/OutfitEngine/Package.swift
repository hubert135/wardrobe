// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OutfitEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OutfitEngine", targets: ["OutfitEngine"])
    ],
    targets: [
        .target(name: "OutfitEngine"),
        .testTarget(name: "OutfitEngineTests", dependencies: ["OutfitEngine"])
    ]
)
