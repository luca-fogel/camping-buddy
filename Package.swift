// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampingCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CampingCore", targets: ["CampingCore"])],
    targets: [
        .target(name: "CampingCore", path: "Core"),
        .testTarget(name: "CampingCoreTests", dependencies: ["CampingCore"], path: "Tests")
    ]
)
