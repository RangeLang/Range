import Foundation
import NeatSyntax

struct SwiftBackendProgramBuilder {
    func build(
        project: SwiftBackendProject,
        semanticProgram: SemanticProgram
    ) throws -> LoweredProgram {
        if project.isSingleFile {
            return try build(
                fromSingleFile: project.projectFiles[0],
                semanticProgram: semanticProgram
            )
        }

        return try build(semanticProgram: semanticProgram)
    }

    private func build(
        fromSingleFile fileURL: URL,
        semanticProgram: SemanticProgram
    ) throws -> LoweredProgram {
        guard
            let parsedFile = semanticProgram.projectExpandedFiles.first(where: {
                $0.path == fileURL.path
            })
        else {
            throw SwiftBackendError("Failed to expand \(fileURL.lastPathComponent).")
        }

        let supportDeclarations = coreSupportDeclarations(in: semanticProgram)
        let supportUnits = coreSupportUnits(for: supportDeclarations)
        let sourceFile = parsedFile.sourceFile

        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .init(
                callables: [],
                enumerations: [],
                declarations: supportDeclarations,
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        enumerations: [],
                        declarations: [],
                        callables: [],
                        mainBlock: mainBlock
                    )
                ] + supportUnits
            )

        case .module(let module):
            guard let mainBlock = module.mainBlock else {
                throw SwiftBackendError(
                    "Swift backend requires a file with @main { ... } when compiling a single file."
                )
            }

            let moduleDeclarations = module.constructs.filter {
                $0.kind == .declaration || $0.kind == .entry
            }

            return .init(
                callables: module.callables,
                enumerations: module.enumerations,
                declarations: supportDeclarations + moduleDeclarations,
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        enumerations: module.enumerations,
                        declarations: moduleDeclarations,
                        callables: module.callables,
                        mainBlock: mainBlock
                    )
                ] + supportUnits
            )

        case .construct, .enumeration, .protocolDefinition, .macro:
            throw SwiftBackendError(
                "Swift backend requires a file with @main { ... } when compiling a single file."
            )

        case .extensions:
            throw SwiftBackendError("Extension-only files cannot be compiled to Swift directly.")
        }
    }

    private func build(semanticProgram: SemanticProgram) throws -> LoweredProgram {
        let supportDeclarations = coreSupportDeclarations(in: semanticProgram)

        var callables: [CallableDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var declarations: [ConstructDeclaration] = supportDeclarations
        var mainBlock: MainBlockNode?
        var units: [LoweredSourceUnit] = coreSupportUnits(for: supportDeclarations)

        for parsedFile in semanticProgram.projectExpandedFiles {
            let fileURL = URL(fileURLWithPath: parsedFile.path)
            let sourceFile = parsedFile.sourceFile
            let outputFileName = fileURL.deletingPathExtension().lastPathComponent + ".swift"

            switch sourceFile {
            case .construct(let declaration):
                if declaration.kind == .declaration || declaration.kind == .entry {
                    declarations.append(declaration)
                }

                units.append(
                    .init(
                        outputFileName: outputFileName,
                        enumerations: [],
                        declarations: declaration.kind == .declaration || declaration.kind == .entry
                            ? [declaration] : [],
                        callables: [],
                        mainBlock: nil
                    )
                )

            case .module(let module):
                callables.append(contentsOf: module.callables)
                enumerations.append(contentsOf: module.enumerations)

                let moduleDeclarations = module.constructs.filter {
                    $0.kind == .declaration || $0.kind == .entry
                }

                units.append(
                    .init(
                        outputFileName: outputFileName,
                        enumerations: module.enumerations,
                        declarations: moduleDeclarations,
                        callables: module.callables,
                        mainBlock: module.mainBlock
                    )
                )

                declarations.append(contentsOf: moduleDeclarations)

                if let block = module.mainBlock {
                    if mainBlock != nil {
                        throw SwiftBackendError(
                            "Found multiple @main modules while generating Swift."
                        )
                    }
                    mainBlock = block
                }

            case .mainBlock(let block):
                if mainBlock != nil {
                    throw SwiftBackendError("Found multiple @main modules while generating Swift.")
                }

                mainBlock = block
                units.append(
                    .init(
                        outputFileName: outputFileName,
                        enumerations: [],
                        declarations: [],
                        callables: [],
                        mainBlock: block
                    )
                )

            case .extensions, .enumeration, .protocolDefinition, .macro:
                continue
            }
        }

        guard let mainBlock else {
            throw SwiftBackendError("Missing @main block while generating Swift.")
        }

        return .init(
            callables: callables,
            enumerations: enumerations,
            declarations: declarations,
            mainBlock: mainBlock,
            units: units
        )
    }

    private func coreSupportDeclarations(in semanticProgram: SemanticProgram) -> [ConstructDeclaration] {
        semanticProgram.expandedFiles.compactMap { parsedFile in
            guard semanticProgram.sourceRole(forPath: parsedFile.path) == .core else {
                return nil
            }

            guard case .construct(let declaration) = parsedFile.sourceFile,
                declaration.isCore,
                declaration.name == "Channel"
            else {
                return nil
            }

            return declaration
        }
    }

    private func coreSupportUnits(for declarations: [ConstructDeclaration]) -> [LoweredSourceUnit] {
        guard !declarations.isEmpty else {
            return []
        }

        return [
            .init(
                outputFileName: "NeatCoreSupport.swift",
                enumerations: [],
                declarations: declarations,
                callables: [],
                mainBlock: nil
            )
        ]
    }
}
