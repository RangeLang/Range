// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GradientBackendSwift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GradientBackendSwift",
            targets: ["GradientBackendSwift"]
        )
    ],
    dependencies: [
        .package(path: "../GradientSyntax")
    ],
    targets: [
        .target(
            name: "GradientBackendSwift",
            dependencies: [
                .product(name: "GradientSyntax", package: "GradientSyntax")
            ],
            path: "Sources",
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .warning),
            ]
        ),
        .testTarget(
            name: "GradientBackendSwiftTests",
            dependencies: ["GradientBackendSwift"],
            path: "Tests"
        )
    ]
)
