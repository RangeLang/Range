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
                "Attributes/Language.md",
                "Attributes/Namespaces.md",
                "Attributes/Packaging.md",
                "Attributes/Syntax.md",
                "Core/CompilerPipeline.md",
                "TypeDefinitions/Enum/Enum.md",
                "TypeDefinitions/Extension/Extension.md",
                "TypeDefinitions/Function/Function.md",
                "TypeDefinitions/Protocol/Protocol.md",
                "GraphBindings/Binding/Binding.md",
                "GraphBindings/Derived/Derived.md",
                "GraphBindings/MemoryGraph/DeclarationGraph.md",
                "GraphBindings/MemoryGraph/MemoryGraph.md",
                "GraphBindings/MemoryGraph/MemoryGraph.ProofRules.md",
                "GraphBindings/State/State.md",
                "GraphBindings/Value/Value.md",
                "ControlFlow/ControlFlow.md",
                "Concurrency/Concurrency.md",
                "Macros/Macros.Context.md",
                "Macros/Macros.ExpressionBlock.md",
                "Macros/Macros.Mapping.md",
                "Macros/Macros.Phase.md",
                "Macros/Macros.md",
                "TypeSystem/Generics.md",
            ],
            swiftSettings: [
                .treatWarning("EmbeddedRestrictions", as: .warning),
            ]
        ),
        .testTarget(
            name: "NeatSyntaxTests",
            dependencies: ["NeatSyntax"],
            path: "Tests/NeatSyntaxTests"
        )
    ]
)
