// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NeatSyntax",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NeatSyntax", targets: ["NeatSyntax"])
    ],
    targets: [
        .target(
            name: "NeatSyntax",
            path: "Sources/NeatSyntax"
        )
    ]
)
