// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RangeCompiler",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RangeCompiler", targets: ["RangeCompiler"]),
        .library(name: "RangeEmission", targets: ["RangeEmission"]),
        .executable(name: "rangec", targets: ["rangec"]),
    ],
    targets: [
        .target(
            name: "RangeCompiler",
            path: "Sources/RangeCompiler",
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .error),
            ]
        ),
        .target(
            name: "RangeEmission",
            dependencies: ["RangeCompiler"],
            path: "Sources/RangeEmission",
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .error),
            ]
        ),
        .executableTarget(
            name: "rangec",
            dependencies: ["RangeCompiler", "RangeEmission"],
            path: "Sources/rangec"
        ),
        .testTarget(
            name: "RangeCompilerTests",
            dependencies: ["RangeCompiler"],
            path: "Tests/RangeCompilerTests"
        ),
        .testTarget(
            name: "RangeEmissionTests",
            dependencies: ["RangeCompiler", "RangeEmission"],
            path: "Tests/RangeEmissionTests"
        ),
    ]
)
