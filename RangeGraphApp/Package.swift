// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RangeGraphApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../RangeSyntax")
    ],
    targets: [
        .executableTarget(
            name: "RangeGraphApp",
            dependencies: [
                .product(name: "RangeSyntax", package: "RangeSyntax")
            ],
            path: "Sources/RangeGraphApp"
        )
    ]
)
