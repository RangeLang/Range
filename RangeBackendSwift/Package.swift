// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RangeBackendSwift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "RangeBackendSwift",
            targets: ["RangeBackendSwift"]
        )
    ],
    dependencies: [
        .package(path: "../RangeSyntax")
    ],
    targets: [
        .target(
            name: "RangeBackendSwift",
            dependencies: [
                .product(name: "RangeSyntax", package: "RangeSyntax")
            ],
            path: "Sources",
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .error),
            ]
        ),
        .testTarget(
            name: "RangeBackendSwiftTests",
            dependencies: ["RangeBackendSwift"],
            path: "Tests"
        )
    ]
)
