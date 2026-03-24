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
            path: "Sources/NeatSyntax",
            exclude: [
                "TypeDefinitions/Construct/Construct.Identity.md",
                "TypeDefinitions/Construct/Construct.Initialization.md",
                "TypeDefinitions/Construct/Construct.md",
                "TypeDefinitions/Enum/Enum.md",
                "TypeDefinitions/Primitive/Primitive.md",
                "TypeDefinitions/Protocol/Protocol.md",
            ]
        )
    ]
)
