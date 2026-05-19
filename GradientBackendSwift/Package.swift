// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NeatBackendSwift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NeatBackendSwift",
            targets: ["NeatBackendSwift"]
        )
    ],
    dependencies: [
        .package(path: "../NeatSyntax")
    ],
    targets: [
        .target(
            name: "NeatBackendSwift",
            dependencies: [
                .product(name: "NeatSyntax", package: "NeatSyntax")
            ],
            path: "Sources",
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .warning),
            ]
        ),
        .testTarget(
            name: "NeatBackendSwiftTests",
            dependencies: ["NeatBackendSwift"],
            path: "Tests"
        )
    ]
)
