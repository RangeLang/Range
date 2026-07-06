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
        .library(name: "SwiftBootstrap", targets: ["SwiftBootstrap"]),
        .executable(name: "range", targets: ["range"]),
    ],
    targets: [
        .target(
            name: "RangeCompiler",
            path: "Sources/RangeCompiler",
            swiftSettings: [.treatWarning("EmbeddedRestrictions", as: .error)]
        ),
        .target(
            name: "RangeEmission",
            dependencies: ["RangeCompiler"],
            path: "Sources/RangeEmission",
            swiftSettings: [.treatWarning("EmbeddedRestrictions", as: .error)]
        ),
        .target(
            name: "SwiftBootstrap",
            dependencies: ["RangeCompiler", "RangeEmission"],
            path: "Sources/SwiftBootstrap",
            swiftSettings: [.treatWarning("EmbeddedRestrictions", as: .error)]
        ),
        .executableTarget(
            name: "range",
            dependencies: ["SwiftBootstrap"],
            path: "Sources/range",
            swiftSettings: [.treatWarning("EmbeddedRestrictions", as: .error)]
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
        .testTarget(
            name: "SwiftBootstrapTests",
            dependencies: ["SwiftBootstrap"],
            path: "Tests/SwiftBootstrapTests"
        ),
    ]
)
