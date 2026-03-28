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
                "Attributes/Core.md",
                "TypeDefinitions/Enum/Enum.md",
                "TypeDefinitions/Extension/Extension.md",
                "TypeDefinitions/Function/Function.md",
                "TypeDefinitions/Protocol/Protocol.md",
                "GraphBindings/Binding/Binding.md",
                "GraphBindings/Derived/Derived.md",
                "GraphBindings/Environment/Environment.md",
                "GraphBindings/MemoryGraph/DeclarationGraph.md",
                "GraphBindings/MemoryGraph/MemoryGraph.md",
                "GraphBindings/MemoryGraph/MemoryGraph.ProofRules.md",
                "GraphBindings/State/State.md",
                "GraphBindings/Value/Value.md",
                "ControlFlow/ControlFlow.md",
                "Macros/Macros.Context.md",
                "Macros/Macros.Freestanding.md",
                "Macros/Macros.Mapping.md",
                "Macros/Macros.md",
                "TypeSystem/Generics.md",
            ]
        )
    ]
)
