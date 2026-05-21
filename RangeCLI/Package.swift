// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RangeCLI",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../RangeSyntax"),
        .package(path: "../RangeBackendSwift"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "RangeCLI",
            dependencies: [
                .product(name: "RangeSyntax", package: "RangeSyntax"),
                .product(name: "RangeBackendSwift", package: "RangeBackendSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            sources: [
                "Commands",
                "RangeCLI",
                "Terminal",
            ],
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .error),
            ]
        ),
        .testTarget(
            name: "RangeCLITests",
            dependencies: ["RangeCLI"],
            path: "Tests/RangeCLITests"
        )
    ]
)
