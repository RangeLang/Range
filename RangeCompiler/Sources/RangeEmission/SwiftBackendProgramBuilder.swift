import Foundation
import RangeCompiler

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
                macrosByName: compiledProgram.declarationGraph.macrosByName,
                callables: [],
                enumerations: [],
                declarations: supportUnits.flatMap(\.declarations),
                extensions: supportUnits.flatMap(\.extensions),
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
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
            let extendedCasesByEnumName = Dictionary(
                grouping: module.extensions.flatMap { extensionDeclaration in
                    extensionDeclaration.enumCases.map { (extensionDeclaration.targetName, $0) }
                },
                by: \.0
            ).mapValues { entries in
                entries.map(\.1)
            }
            let moduleEnumerations = mergeExtendedEnumCases(
                into: module.enumerations,
                extendedCasesByEnumName: extendedCasesByEnumName
            )

            return .init(
                macrosByName: compiledProgram.declarationGraph.macrosByName,
                callables: module.callables,
                enumerations: moduleEnumerations,
                declarations: supportUnits.flatMap(\.declarations) + moduleDeclarations,
                extensions: supportUnits.flatMap(\.extensions) + module.extensions,
                mainBlock: mainBlock,
                units: [
                    .init(
                        outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        enumerations: moduleEnumerations,
                        declarations: moduleDeclarations,
                        extensions: module.extensions,
                        callables: module.callables,
                        mainBlock: mainBlock
                    )
                ] + supportUnits
            )

        case .construct, .enumeration, .macro:
            throw SwiftBackendError(
                "Swift backend requires a file with @main { ... } when compiling a single file."
            )

        case .extensions:
            throw SwiftBackendError("Extension-only files cannot be compiled to Swift directly.")
        }
    }

    private func build(compiledProgram: CompiledProgram) throws -> LoweredProgram {
        var callables: [CallableDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var declarations: [ConstructDeclaration] = []
        var extensions: [ExtensionDeclaration] = []
        var mainBlock: MainBlockNode?
        var units: [LoweredSourceUnit] = coreSupportUnits(in: compiledProgram)

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
                enumerations.append(contentsOf: module.enumerations)
                extensions.append(contentsOf: module.extensions)

                let moduleDeclarations = module.constructs.filter {
                    $0.kind == .declaration || $0.kind == .entry
                }

                units.append(
                    .init(
                        outputFileName: outputFileName,
                        enumerations: module.enumerations,
                        declarations: moduleDeclarations,
                        extensions: module.extensions,
                        callables: module.callables,
                        mainBlock: module.mainBlock
                    )
                )

                declarations.append(contentsOf: moduleDeclarations)

                if mainBlock == nil, let block = module.mainBlock {
                    mainBlock = block
                }

            case .mainBlock(let block):
                if mainBlock == nil {
                    mainBlock = block
                }
                units.append(
                    .init(
                        outputFileName: outputFileName,
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
                        enumerations: [declaration],
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
                        enumerations: declarations.flatMap(\.enumerations),
                        declarations: declarations.flatMap(\.constructs),
                        extensions: declarations,
                        callables: [],
                        mainBlock: nil
                    )
                )

            case .macro:
                continue
            }
        }

        guard let mainBlock else {
            throw SwiftBackendError("Missing @main block while generating Swift.")
        }

        let extendedCasesByEnumName = Dictionary(
            grouping: extensions.flatMap { extensionDeclaration in
                extensionDeclaration.enumCases.map { (extensionDeclaration.targetName, $0) }
            },
            by: \.0
        ).mapValues { entries in
            entries.map(\.1)
        }
        let loweredEnumerations = mergeExtendedEnumCases(
            into: enumerations,
            extendedCasesByEnumName: extendedCasesByEnumName
        )
        let loweredUnits = units.map { unit in
            LoweredSourceUnit(
                outputFileName: unit.outputFileName,
                enumerations: mergeExtendedEnumCases(
                    into: unit.enumerations,
                    extendedCasesByEnumName: extendedCasesByEnumName
                ),
                declarations: unit.declarations,
                extensions: unit.extensions,
                callables: unit.callables,
                mainBlock: unit.mainBlock
            )
        }

        return .init(
            macrosByName: compiledProgram.declarationGraph.macrosByName,
            callables: callables,
            enumerations: loweredEnumerations,
            declarations: declarations,
            extensions: extensions,
            mainBlock: mainBlock,
            units: loweredUnits
        )
    }

    private func mergeExtendedEnumCases(
        into enumerations: [EnumDeclaration],
        extendedCasesByEnumName: [String: [EnumCaseDeclaration]]
    ) -> [EnumDeclaration] {
        enumerations.map { declaration in
            guard let extensionCases = extendedCasesByEnumName[declaration.name],
                !extensionCases.isEmpty
            else {
                return declaration
            }
            return EnumDeclaration(
                macros: declaration.macros,
                extensibility: declaration.extensibility,
                attribute: declaration.attribute,
                name: declaration.name,
                genericParameters: declaration.genericParameters,
                conformances: [],
                cases: declaration.cases + extensionCases
            )
        }
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
        let includeSyntaxLexingSupport = projectUsesSyntaxLexingSupport(compiledProgram)
            || rangeProgramUsesSyntaxLexingSupport(compiledProgram)
        let coreUnits = compiledProgram.expandedFiles.compactMap { parsedFile -> LoweredSourceUnit? in
            guard compiledProgram.sourceRole(forPath: parsedFile.path) == .core,
                isCorePath(parsedFile.path, containing: "Encoding/")
                    || (includeSyntaxLexingSupport
                        && isCorePath(parsedFile.path, containing: "Syntax/Lexing/"))
                    || (includeSyntaxLexingSupport
                        && parsedFile.path.contains("/RangeCompiler/Range/Lexer/"))
                    || (includeSyntaxLexingSupport
                        && isCorePath(parsedFile.path, containing: "Syntax/Identifier.range"))
                    || (includeSyntaxLexingSupport
                        && isCorePath(parsedFile.path, containing: "Macro/SyntaxEmittable.range"))
                    || isCorePath(parsedFile.path, containing: "Syntax/Program/")
                    || isCorePath(parsedFile.path, containing: "System/File/")
                    || isCorePath(parsedFile.path, containing: "System/Memory/")
                    || isCorePath(parsedFile.path, containing: "System/Thread/")
            else {
                return nil
            }

            let fileURL = URL(fileURLWithPath: parsedFile.path)
            let outputFileName = "RangeCore_\(fileURL.deletingPathExtension().lastPathComponent).swift"

            switch parsedFile.sourceFile {
            case .construct(let declaration):
                guard shouldEmitCoreSupportConstruct(declaration, in: parsedFile.path) else {
                    return nil
                }

                return .init(
                    outputFileName: outputFileName,
                    enumerations: [],
                    declarations: [declaration],
                    extensions: [],
                    callables: [],
                    mainBlock: nil
                )
            case .enumeration(let declaration):
                return .init(
                    outputFileName: outputFileName,
                    enumerations: [declaration],
                    declarations: [],
                    extensions: [],
                    callables: [],
                    mainBlock: nil
                )
            case .extensions(let declarations):
                return .init(
                    outputFileName: outputFileName,
                    enumerations: declarations.flatMap(\.enumerations),
                    declarations: declarations.flatMap(\.constructs),
                    extensions: declarations,
                    callables: [],
                    mainBlock: nil
                )
            case .module(let module):
                let declarations = module.constructs.filter {
                    ($0.kind == .declaration || $0.kind == .entry)
                        && shouldEmitCoreSupportConstruct($0, in: parsedFile.path)
                }

                return .init(
                    outputFileName: outputFileName,
                    enumerations: module.enumerations,
                    declarations: declarations,
                    extensions: module.extensions,
                    callables: module.callables,
                    mainBlock: nil
                )
            case .mainBlock, .macro:
                return nil
            }
        }

        let channelDeclarations = coreSupportDeclarations(in: compiledProgram)
        guard !channelDeclarations.isEmpty else {
            return coreUnits
        }

        return [
            .init(
                outputFileName: "RangeCoreSupport.swift",
                enumerations: [],
                declarations: channelDeclarations,
                extensions: [],
                callables: [],
                mainBlock: nil
            )
        ] + coreUnits
    }

    private func projectUsesSyntaxLexingSupport(_ compiledProgram: CompiledProgram) -> Bool {
        compiledProgram.projectExpandedFiles.contains { parsedFile in
            parsedFile.path.contains("/Syntax/")
                || parsedFile.source?.contains("Lexer") == true
                || parsedFile.source?.contains("Lexing") == true
                || parsedFile.source?.contains("LexicalToken") == true
                || parsedFile.source?.contains("rangeLexer") == true
        }
    }

    private func rangeProgramUsesSyntaxLexingSupport(_ compiledProgram: CompiledProgram) -> Bool {
        compiledProgram.expandedFiles.contains { parsedFile in
            compiledProgram.sourceRole(forPath: parsedFile.path) == .core
                && isCorePath(parsedFile.path, containing: "Syntax/Program/")
                && parsedFile.source?.contains("LexicalToken") == true
        }
    }

    private func shouldEmitCoreSupportConstruct(
        _ declaration: ConstructDeclaration,
        in path: String
    ) -> Bool {
        if isCorePath(path, containing: "System/File/") {
            return declaration.name != "HostFileSystem"
                && declaration.name != "FileManager"
                && declaration.name != "UTF8"
        }

        if isCorePath(path, containing: "System/Memory/") {
            return declaration.name != "POSIXMemory"
                && declaration.name != "Memory"
                && declaration.name != "CPU"
        }

        if isCorePath(path, containing: "System/Thread/") {
            return declaration.name != "POSIXThread"
                && declaration.name != "Thread"
        }

        return true
    }

    private func isCorePath(_ path: String, containing suffix: String) -> Bool {
        path.contains("/RangeCore/\(suffix)") || path.contains("/RangeCompiler/Range/Core/\(suffix)")
    }
}
