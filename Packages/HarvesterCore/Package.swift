// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HarvesterCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HarvesterCore", targets: ["HarvesterCore"]),
    ],
    targets: [
        .target(name: "HarvesterCore"),
        .testTarget(
            name: "HarvesterCoreTests",
            dependencies: ["HarvesterCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
