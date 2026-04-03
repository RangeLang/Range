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
        .package(path: "../NeatSyntax"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "NeatBackendSwift",
            dependencies: [
                .product(name: "NeatSyntax", package: "NeatSyntax"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"
        )
    ]
)
