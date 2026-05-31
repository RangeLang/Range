// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CLI",
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
            name: "CLI",
            dependencies: [
                .product(name: "RangeSyntax", package: "RangeSyntax"),
                .product(name: "RangeBackendSwift", package: "RangeBackendSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            sources: [
                "Commands",
                "CLI",
                "Terminal",
            ],
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .error),
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["CLI"],
            path: "Tests/CLITests"
        )
    ]
)
