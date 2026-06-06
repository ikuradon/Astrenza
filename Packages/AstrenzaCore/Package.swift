// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AstrenzaCore",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "AstrenzaCore", targets: ["AstrenzaCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/jb55/secp256k1.swift", revision: "40b4b38b3b1c83f7088c76189a742870e0ca06a9"),
        .package(url: "https://github.com/damus-io/negentropy-swift", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "AstrenzaCore",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift"),
                .product(name: "Negentropy", package: "negentropy-swift")
            ]
        ),
        .testTarget(
            name: "AstrenzaCoreTests",
            dependencies: [
                "AstrenzaCore",
                .product(name: "secp256k1", package: "secp256k1.swift")
            ]
        )
    ]
)
