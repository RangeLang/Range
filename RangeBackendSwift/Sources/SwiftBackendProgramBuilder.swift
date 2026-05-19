import Foundation
import RangeSyntax

struct SwiftBackendProgramBuilder {
    func build(
        project: SwiftBackendProject,
        compiledProgram: CompiledProgram
    ) throws -> LoweredProgram {
        if project.isSingleFile {
            return try build(
                fromSingleFile: project.projectFiles[0],
                compiledProgram: compiledProgram
            )
        }

        return try build(compiledProgram: compiledProgram)
    }

    private func build(
        fromSingleFile fileURL: URL,
        compiledProgram: CompiledProgram
    ) throws -> LoweredProgram {
        guard
            let parsedFile = compiledProgram.projectExpandedFiles.first(where: {
                $0.path == fileURL.path
            })
        else {
            throw SwiftBackendError("Failed to expand \(fileURL.lastPathComponent).")
        }

        let supportUnits = coreSupportUnits(in: compiledProgram)
        let sourceFile = parsedFile.sourceFile

        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .init(
                callables: [],
                protocols: supportUnits.flatMap(\.protocols),
                enumerations: [],
                declarations: supportUnits.flatMap(\.declarations),
                extensions: supportUnits.flatMap(\.extensions),
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        protocols: [],
                        enumerations: [],
                        declarations: [],
                        extensions: [],
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
                protocols: supportUnits.flatMap(\.protocols) + module.protocols,
                enumerations: module.enumerations,
                declarations: supportUnits.flatMap(\.declarations) + moduleDeclarations,
                extensions: supportUnits.flatMap(\.extensions) + module.extensions,
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        protocols: module.protocols,
                        enumerations: module.enumerations,
                        declarations: moduleDeclarations,
                        extensions: module.extensions,
                        callables: module.callables,
                        mainBlock: mainBlock
                    )
                ] + supportUnits
            )

        case .construct, .namespace, .enumeration, .protocolDefinition, .macro, .marker:
            throw SwiftBackendError(
                "Swift backend requires a file with @main { ... } when compiling a single file."
            )

        case .extensions:
            throw SwiftBackendError("Extension-only files cannot be compiled to Swift directly.")
        }
    }

    private func build(compiledProgram: CompiledProgram) throws -> LoweredProgram {
        var callables: [CallableDeclaration] = []
        var protocols: [ProtocolDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var declarations: [ConstructDeclaration] = []
        var extensions: [ExtensionDeclaration] = []
        var mainBlock: MainBlockNode?
        var units: [LoweredSourceUnit] = coreSupportUnits(in: compiledProgram)

        protocols.append(contentsOf: units.flatMap(\.protocols))
        enumerations.append(contentsOf: units.flatMap(\.enumerations))
        declarations.append(contentsOf: units.flatMap(\.declarations))
        extensions.append(contentsOf: units.flatMap(\.extensions))

        for parsedFile in compiledProgram.projectExpandedFiles {
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
                        protocols: [],
                        enumerations: [],
                        declarations: declaration.kind == .declaration || declaration.kind == .entry
                            ? [declaration] : [],
                        extensions: [],
                        callables: [],
                        mainBlock: nil
                    )
                )

            case .module(let module):
                callables.append(contentsOf: module.callables)
                protocols.append(contentsOf: module.protocols)
                enumerations.append(contentsOf: module.enumerations)
                extensions.append(contentsOf: module.extensions)

                let moduleDeclarations = module.constructs.filter {
                    $0.kind == .declaration || $0.kind == .entry
                }

                units.append(
                    .init(
                        outputFileName: outputFileName,
                        protocols: module.protocols,
                        enumerations: module.enumerations,
                        declarations: moduleDeclarations,
                        extensions: module.extensions,
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
                        protocols: [],
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: [],
                        mainBlock: block
                    )
                )

            case .enumeration(let declaration):
                enumerations.append(declaration)
                units.append(
                    .init(
                        outputFileName: outputFileName,
                        protocols: [],
                        enumerations: [declaration],
                        declarations: [],
                        extensions: [],
                        callables: [],
                        mainBlock: nil
                    )
                )

            case .protocolDefinition(let declaration):
                protocols.append(declaration)
                units.append(
                    .init(
                        outputFileName: outputFileName,
                        protocols: [declaration],
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: [],
                        mainBlock: nil
                    )
                )

            case .extensions(let declarations):
                extensions.append(contentsOf: declarations)
                units.append(
                    .init(
                        outputFileName: outputFileName,
                        protocols: [],
                        enumerations: declarations.flatMap(\.enumerations),
                        declarations: declarations.flatMap(\.constructs),
                        extensions: declarations,
                        callables: [],
                        mainBlock: nil
                    )
                )

            case .namespace, .macro, .marker:
                continue
            }
        }

        guard let mainBlock else {
            throw SwiftBackendError("Missing @main block while generating Swift.")
        }

        return .init(
            callables: callables,
            protocols: protocols,
            enumerations: enumerations,
            declarations: declarations,
            extensions: extensions,
            mainBlock: mainBlock,
            units: units
        )
    }

    private func coreSupportDeclarations(in compiledProgram: CompiledProgram) -> [ConstructDeclaration] {
        compiledProgram.expandedFiles.flatMap { parsedFile -> [ConstructDeclaration] in
            guard compiledProgram.sourceRole(forPath: parsedFile.path) == .core else {
                return []
            }

            let declarations: [ConstructDeclaration]
            switch parsedFile.sourceFile {
            case .construct(let declaration):
                declarations = [declaration]
            case .module(let module):
                declarations = module.constructs
            default:
                declarations = []
            }

            return declarations.filter {
                $0.isCore && $0.name == "Channel"
            }
        }
    }

    private func coreSupportUnits(in compiledProgram: CompiledProgram) -> [LoweredSourceUnit] {
        let encodingUnits = compiledProgram.expandedFiles.compactMap { parsedFile -> LoweredSourceUnit? in
            guard compiledProgram.sourceRole(forPath: parsedFile.path) == .core,
                parsedFile.path.contains("/RangeCore/Encoding/")
            else {
                return nil
            }

            let fileURL = URL(fileURLWithPath: parsedFile.path)
            let outputFileName = "RangeCore_\(fileURL.deletingPathExtension().lastPathComponent).swift"

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                return .init(
                    outputFileName: outputFileName,
                    protocols: [],
                    enumerations: [],
                    declarations: [declaration],
                    extensions: [],
                    callables: [],
                    mainBlock: nil
                )
            case .enumeration(let declaration):
                return .init(
                    outputFileName: outputFileName,
                    protocols: [],
                    enumerations: [declaration],
                    declarations: [],
                    extensions: [],
                    callables: [],
                    mainBlock: nil
                )
            case .protocolDefinition(let declaration):
                return .init(
                    outputFileName: outputFileName,
                    protocols: [declaration],
                    enumerations: [],
                    declarations: [],
                    extensions: [],
                    callables: [],
                    mainBlock: nil
                )
            case .extensions(let declarations):
                return .init(
                    outputFileName: outputFileName,
                    protocols: [],
                    enumerations: declarations.flatMap(\.enumerations),
                    declarations: declarations.flatMap(\.constructs),
                    extensions: declarations,
                    callables: [],
                    mainBlock: nil
                )
            case .module(let module):
                return .init(
                    outputFileName: outputFileName,
                    protocols: module.protocols,
                    enumerations: module.enumerations,
                    declarations: module.constructs.filter {
                        $0.kind == .declaration || $0.kind == .entry
                    },
                    extensions: module.extensions,
                    callables: module.callables,
                    mainBlock: nil
                )
            case .mainBlock, .namespace, .macro, .marker:
                return nil
            }
        }

        let channelDeclarations = coreSupportDeclarations(in: compiledProgram)
        guard !channelDeclarations.isEmpty else {
            return encodingUnits
        }

        return [
            .init(
                outputFileName: "RangeCoreSupport.swift",
                protocols: [],
                enumerations: [],
                declarations: channelDeclarations,
                extensions: [],
                callables: [],
                mainBlock: nil
            )
        ] + encodingUnits
    }
}
