// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RangeSyntax",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RangeSyntax", targets: ["RangeSyntax"])
    ],
    targets: [
        .target(
            name: "RangeSyntax",
            path: "Sources/RangeSyntax",
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .error),
            ]
        ),
        .testTarget(
            name: "RangeSyntaxTests",
            dependencies: ["RangeSyntax"],
            path: "Tests/RangeSyntaxTests"
        )
    ]
)
