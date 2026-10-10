// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Harvest",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // xtool builds the single library product into the app.
        .library(name: "Harvest", targets: ["Harvest"]),
    ],
    dependencies: [
        .package(path: "Packages/HarvesterCore"),
    ],
    targets: [
        .target(
            name: "Harvest",
            dependencies: [
                .product(name: "HarvesterCore", package: "HarvesterCore"),
            ],
            // Xcode uses the asset catalog; xtool takes the icon from Support/AppIcon.png instead.
            exclude: ["Assets.xcassets"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
