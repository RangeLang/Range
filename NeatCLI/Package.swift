// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NeatCLI",
    products: [
        .library(name: "NeatSyntax", targets: ["NeatSyntax"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "NeatSyntax",
            path: "Sources/NeatSyntax"
        ),
        .executableTarget(
            name: "NeatCLI",
            dependencies: [
                "NeatSyntax",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            exclude: [
                "NeatSyntax"
            ],
            resources: [
                .process("NeatCLI/Templates")
            ]
        ),
    ]
)
