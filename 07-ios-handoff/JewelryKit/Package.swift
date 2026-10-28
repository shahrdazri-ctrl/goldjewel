// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JewelryKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "JewelryKit", targets: ["JewelryKit"])
    ],
    targets: [
        .target(
            name: "JewelryKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "JewelryKitTests",
            dependencies: ["JewelryKit"],
            resources: [.process("Fixtures")]
        )
    ]
)
