// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CLI",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../RangeCompiler"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "CLI",
            dependencies: [
                .product(name: "RangeCompiler", package: "RangeCompiler"),
                .product(name: "RangeEmission", package: "RangeCompiler"),
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
