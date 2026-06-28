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

    func buildLLVM(
        project: SwiftBackendProject,
        compiledProgram: CompiledProgram
    ) throws -> LoweredProgram {
        try build(compiledProgram: compiledProgram, requireMain: false)
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

        let module = parsedFile.sourceFile
        guard let mainBlock = synthesizedMainBlock(in: module) else {
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
            callables: [],
            enumerations: moduleEnumerations,
            declarations: moduleDeclarations,
            extensions: module.extensions,
            mainBlock: mainBlock,
            units: [
                .init(
                    outputFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                    enumerations: moduleEnumerations,
                    declarations: moduleDeclarations,
                    extensions: module.extensions,
                    callables: [],
                    mainBlock: mainBlock
                )
            ]
        )
    }

    private func build(
        compiledProgram: CompiledProgram,
        requireMain: Bool = true
    ) throws -> LoweredProgram {
        let callables: [CallableDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var declarations: [ConstructDeclaration] = []
        var extensions: [ExtensionDeclaration] = []
        var mainBlock: BlockMacroNode?
        var units: [LoweredSourceUnit] = []

        for parsedFile in compiledProgram.projectExpandedFiles {
            let fileURL = URL(fileURLWithPath: parsedFile.path)
            let outputFileName = fileURL.deletingPathExtension().lastPathComponent + ".swift"

            let module = parsedFile.sourceFile
            enumerations.append(contentsOf: module.enumerations)
            extensions.append(contentsOf: module.extensions)
            let unitMainBlock = synthesizedMainBlock(in: module)

            let moduleDeclarations = module.constructs.filter {
                $0.kind == .declaration || $0.kind == .entry
            }

            units.append(
                .init(
                    outputFileName: outputFileName,
                    enumerations: module.enumerations,
                    declarations: moduleDeclarations,
                    extensions: module.extensions,
                    callables: [],
                    mainBlock: unitMainBlock
                )
            )

            declarations.append(contentsOf: moduleDeclarations)

            if mainBlock == nil, let block = unitMainBlock {
                mainBlock = block
            }
        }

        if requireMain && mainBlock == nil {
            throw SwiftBackendError("Missing @main block while generating Swift.")
        }
        let loweredMainBlock = mainBlock ?? BlockMacroNode(macros: [], body: [])
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
            mainBlock: loweredMainBlock,
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

    private func synthesizedMainBlock(in module: ModuleFileNode) -> BlockMacroNode? {
        guard let block = module.blockMacros.first(where: { $0.macros.first?.name == "main" })
        else {
            return nil
        }
        return block
    }

}
