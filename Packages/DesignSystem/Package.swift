// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    targets: [
        .target(name: "DesignSystem"),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)
