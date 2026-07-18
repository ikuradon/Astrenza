// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AstrenzaCore",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "AstrenzaCore", targets: ["AstrenzaCore"]),
        .library(name: "NostrProtocol", targets: ["NostrProtocol"]),
        .library(name: "NostrCryptoAPI", targets: ["NostrCryptoAPI"]),
        .library(name: "NostrCryptoSecp256k1", targets: ["NostrCryptoSecp256k1"]),
        .library(name: "NostrReconciliationAPI", targets: ["NostrReconciliationAPI"]),
        .library(name: "NostrReconciliationNegentropy", targets: ["NostrReconciliationNegentropy"]),
        .library(name: "NostrStoreAPI", targets: ["NostrStoreAPI"]),
        .library(name: "NostrStoreGRDB", targets: ["NostrStoreGRDB"]),
        .library(name: "NostrRelay", targets: ["NostrRelay"]),
        .library(name: "NostrSync", targets: ["NostrSync"]),
        .library(name: "NostrHomeFeature", targets: ["NostrHomeFeature"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        .package(url: "https://github.com/jb55/secp256k1.swift", revision: "40b4b38b3b1c83f7088c76189a742870e0ca06a9"),
        .package(url: "https://github.com/damus-io/negentropy-swift", from: "0.1.0")
    ],
    targets: [
        .target(name: "NostrProtocol"),
        .target(
            name: "NostrCryptoAPI",
            dependencies: ["NostrProtocol"]
        ),
        .target(
            name: "NostrCryptoSecp256k1",
            dependencies: [
                "NostrProtocol",
                "NostrCryptoAPI",
                .product(name: "secp256k1", package: "secp256k1.swift")
            ]
        ),
        .target(name: "NostrReconciliationAPI"),
        .target(
            name: "NostrReconciliationNegentropy",
            dependencies: [
                "NostrReconciliationAPI",
                .product(name: "Negentropy", package: "negentropy-swift")
            ]
        ),
        .target(
            name: "NostrStoreAPI",
            dependencies: ["NostrProtocol"]
        ),
        .target(
            name: "NostrStoreGRDB",
            dependencies: [
                "NostrProtocol",
                "NostrStoreAPI",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "NostrRelay",
            dependencies: [
                "NostrProtocol",
                "NostrCryptoAPI",
                "NostrStoreAPI"
            ]
        ),
        .target(
            name: "NostrSync",
            dependencies: [
                "NostrProtocol",
                "NostrCryptoAPI",
                "NostrReconciliationAPI",
                "NostrStoreAPI",
                "NostrRelay"
            ]
        ),
        .target(
            name: "NostrHomeFeature",
            dependencies: [
                "NostrProtocol",
                "NostrStoreAPI",
                "NostrRelay",
                "NostrSync"
            ]
        ),
        .target(
            name: "AstrenzaCore",
            dependencies: [
                "NostrProtocol",
                "NostrCryptoAPI",
                "NostrCryptoSecp256k1",
                "NostrReconciliationAPI",
                "NostrReconciliationNegentropy",
                "NostrStoreAPI",
                "NostrStoreGRDB",
                "NostrRelay",
                "NostrSync",
                "NostrHomeFeature"
            ]
        ),
        .testTarget(
            name: "AstrenzaCoreTests",
            dependencies: [
                "AstrenzaCore",
                "NostrSync",
                .product(name: "secp256k1", package: "secp256k1.swift")
            ]
        ),
        .testTarget(
            name: "NostrProtocolTests",
            dependencies: ["NostrProtocol"]
        ),
        .testTarget(
            name: "NostrCryptoSecp256k1Tests",
            dependencies: [
                "NostrProtocol",
                "NostrCryptoAPI",
                "NostrCryptoSecp256k1"
            ]
        ),
        .testTarget(
            name: "NostrReconciliationNegentropyTests",
            dependencies: [
                "NostrReconciliationAPI",
                "NostrReconciliationNegentropy"
            ]
        ),
        .testTarget(
            name: "NostrStoreGRDBTests",
            dependencies: [
                "NostrProtocol",
                "NostrStoreAPI",
                "NostrStoreGRDB"
            ]
        ),
        .testTarget(
            name: "NostrRelayTests",
            dependencies: ["NostrRelay"]
        ),
        .testTarget(
            name: "NostrSyncTests",
            dependencies: [
                "NostrProtocol",
                "NostrReconciliationAPI",
                "NostrRelay",
                "NostrSync"
            ]
        ),
        .testTarget(
            name: "NostrHomeFeatureTests",
            dependencies: [
                "NostrProtocol",
                "NostrRelay",
                "NostrSync",
                "NostrHomeFeature"
            ]
        )
    ]
)
