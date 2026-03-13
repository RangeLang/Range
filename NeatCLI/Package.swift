// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NeatCLI",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../NeatSyntax"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "NeatCLI",
            dependencies: [
                .product(name: "NeatSyntax", package: "NeatSyntax"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            resources: [
                .process("NeatCLI/Templates")
            ]
        )
    ]
)
