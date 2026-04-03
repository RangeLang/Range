import Foundation
import NeatSyntax

struct SwiftBackendProgramBuilder {
    func build(
        project: SwiftBackendProject,
        semanticProgram: SemanticProgram
    ) throws -> LoweredProgram {
        if project.isSingleFile {
            return try build(
                fromSingleFile: project.projectFiles[0], semanticProgram: semanticProgram)
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
        let sourceFile = parsedFile.sourceFile
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .init(
                callables: [],
                declarations: [],
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent
                            + ".swift",
                        declarations: [],
                        callables: [],
                        mainBlock: mainBlock
                    )
                ]
            )
        case .module(let module):
            guard let mainBlock = module.mainBlock else {
                throw SwiftBackendError(
                    "Swift backend requires a file with @main { ... } when compiling a single file."
                )
            }
            return .init(
                callables: module.callables,
                declarations: module.constructs.filter {
                    $0.kind == .declaration || $0.kind == .entry
                },
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent
                            + ".swift",
                        declarations: module.constructs.filter {
                            $0.kind == .declaration || $0.kind == .entry
                        },
                        callables: module.callables,
                        mainBlock: mainBlock
                    )
                ]
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
        var callables: [CallableDeclaration] = []
        var declarations: [ConstructDeclaration] = []
        var mainBlock: MainBlockNode?
        var units: [LoweredSourceUnit] = []

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
                        declarations: declaration.kind == .declaration || declaration.kind == .entry
                            ? [declaration] : [],
                        callables: [],
                        mainBlock: nil
                    )
                )
            case .module(let module):
                callables.append(contentsOf: module.callables)
                units.append(
                    .init(
                        outputFileName: outputFileName,
                        declarations: module.constructs.filter {
                            $0.kind == .declaration || $0.kind == .entry
                        },
                        callables: module.callables,
                        mainBlock: module.mainBlock
                    )
                )
                declarations.append(
                    contentsOf: module.constructs.filter {
                        $0.kind == .declaration || $0.kind == .entry
                    }
                )
                if let block = module.mainBlock {
                    if mainBlock != nil {
                        throw SwiftBackendError(
                            "Found multiple @main modules while generating Swift.")
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
            declarations: declarations,
            mainBlock: mainBlock,
            units: units
        )
    }
}
