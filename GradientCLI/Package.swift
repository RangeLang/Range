// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GradientCLI",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../GradientSyntax"),
        .package(path: "../GradientBackendSwift"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "GradientCLI",
            dependencies: [
                .product(name: "GradientSyntax", package: "GradientSyntax"),
                .product(name: "GradientBackendSwift", package: "GradientBackendSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            sources: [
                "Commands",
                "GradientCLI",
                "Terminal",
            ],
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .warning),
            ]
        ),
        .testTarget(
            name: "GradientCLITests",
            dependencies: ["GradientCLI"],
            path: "Tests/GradientCLITests"
        )
    ]
)
