import Foundation

public enum SourceInputRole {
    case core
    case macroOnly
    case project

    public var isCore: Bool {
        switch self {
        case .core:
            return true
        case .macroOnly, .project:
            return false
        }
    }

}

public struct SourceInput {
    public let path: String
    public let source: String
    public let role: SourceInputRole

    public init(path: String, source: String, role: SourceInputRole) {
        self.path = path
        self.source = source
        self.role = role
    }
}

public struct CompiledProgram {
    public let inputs: [SourceInput]
    public let parsedFiles: [ParsedSourceFile]
    public let expandedFiles: [ParsedSourceFile]
    public let declarationGraph: DeclarationGraph

    private let inputRoleByPath: [String: SourceInputRole]

    public init(
        inputs: [SourceInput],
        parsedFiles: [ParsedSourceFile],
        expandedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) {
        self.inputs = inputs
        self.parsedFiles = parsedFiles
        self.expandedFiles = expandedFiles
        self.declarationGraph = declarationGraph
        self.inputRoleByPath = Dictionary(
            uniqueKeysWithValues: inputs.map { ($0.path, $0.role) }
        )
    }

    public var declarationViews: DeclarationGraphViews {
        declarationGraph.views
    }

    public var literalBridgeResolver: LiteralBridgeResolver {
        declarationViews.literalBridgeResolver
    }

    public var projectParsedFiles: [ParsedSourceFile] {
        parsedFiles.filter { path in
            guard let role = inputRoleByPath[path.path] else { return false }
            return !role.isCore
        }
    }

    public var projectExpandedFiles: [ParsedSourceFile] {
        expandedFiles.filter { path in
            guard let role = inputRoleByPath[path.path] else { return false }
            return !role.isCore
        }
    }

}

public struct CompilerPipeline {
    public init() {}

    private func inputRolePriority(_ role: SourceInputRole) -> Int {
        switch role {
        case .core:
            return 0
        case .macroOnly:
            return 1
        case .project:
            return 2
        }
    }

    public func build(
        inputs: [SourceInput],
        diagnosticEngine: RangeDiagnosticEngine? = nil
    ) throws -> CompiledProgram {
        let orderedInputs = inputs.sorted { lhs, rhs in
            let lhsRolePriority = inputRolePriority(lhs.role)
            let rhsRolePriority = inputRolePriority(rhs.role)
            if lhsRolePriority != rhsRolePriority {
                return lhsRolePriority < rhsRolePriority
            }
            return lhs.path < rhs.path
        }

        let coreInputs = orderedInputs.filter { $0.role.isCore }
        let projectInputs = orderedInputs.filter { !$0.role.isCore }

        let discoveredCoreDeclarationFiles = try discoverProjectDeclarationFiles(
            inputs: coreInputs
        )
        let discoveredCoreGraph = DeclarationGraph(files: discoveredCoreDeclarationFiles)
        let discoveredCoreViews = discoveredCoreGraph.views
        let discoveredCoreMacrosByName = MacroExpander.collectMacroDeclarations(
            from: discoveredCoreDeclarationFiles
        )
        let discoveredCoreMacroMetadataByName = MacroExpander.collectMacroMetadata(
            from: discoveredCoreDeclarationFiles
        )
        let discoveredCoreMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(
            from: discoveredCoreDeclarationFiles
        )
        let parsedCoreFiles = try parse(
            inputs: coreInputs,
            literalBridgeResolver: discoveredCoreViews.literalBridgeResolver,
            declarationMemberResolver: discoveredCoreViews.memberResolver,
            declarationOperatorResolver: discoveredCoreViews.operatorResolver,
            declarationMacroExpansionResolver: DeclarationMacroExpansionResolver(
                macrosByName: discoveredCoreMacrosByName
            ),
            macroDeclarationsByName: discoveredCoreMacrosByName,
            macroMetadataDeclarationsByName: discoveredCoreMacroMetadataByName,
            macroExpansionTypes: discoveredCoreMacroExpansionTypes
        )

        let coreMacrosByName = MacroExpander.collectMacroDeclarations(from: parsedCoreFiles)
        let coreMacroMetadataByName = MacroExpander.collectMacroMetadata(from: parsedCoreFiles)
        let coreMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(from: parsedCoreFiles)
        let discoveredProjectDeclarationFiles = try discoverProjectDeclarationFiles(
            inputs: projectInputs,
            macroDeclarationsByName: coreMacrosByName,
            macroMetadataDeclarationsByName: coreMacroMetadataByName
        )
        let discoveredProjectGraph = DeclarationGraph(
            files: parsedCoreFiles + discoveredProjectDeclarationFiles
        )
        let discoveredProjectViews = discoveredProjectGraph.views
        let discoveredProjectMacrosByName = MacroExpander.collectMacroDeclarations(
            from: discoveredProjectDeclarationFiles
        )
        let discoveredProjectMacroMetadataByName = MacroExpander.collectMacroMetadata(
            from: discoveredProjectDeclarationFiles
        )
        let discoveredProjectMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(
            from: discoveredProjectDeclarationFiles
        )
        let projectMacrosByName = coreMacrosByName.merging(discoveredProjectMacrosByName) { _, new in
            new
        }
        let projectMacroMetadataByName = coreMacroMetadataByName.merging(discoveredProjectMacroMetadataByName) {
            _, new in new
        }
        let parsedProjectFiles = try parse(
            inputs: projectInputs,
            literalBridgeResolver: discoveredProjectViews.literalBridgeResolver,
            declarationMemberResolver: discoveredProjectViews.memberResolver,
            declarationOperatorResolver: discoveredProjectViews.operatorResolver,
            declarationMacroExpansionResolver: DeclarationMacroExpansionResolver(
                macrosByName: projectMacrosByName
            ),
            macroDeclarationsByName: projectMacrosByName,
            macroMetadataDeclarationsByName: projectMacroMetadataByName,
            macroExpansionTypes: coreMacroExpansionTypes.merging(
                discoveredProjectMacroExpansionTypes
            ) { _, new in new }
        )

        let parsedFiles = parsedCoreFiles + parsedProjectFiles

        let expandedFiles = try MacroExpander.expand(
            files: parsedFiles,
            diagnosticEngine: diagnosticEngine
        )
        let declarationGraph = DeclarationGraph(files: expandedFiles)

        return CompiledProgram(
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            declarationGraph: declarationGraph
        )
    }

    public func diagnostics(inputs: [SourceInput], fallbackPath: String? = nil) -> [RangeDiagnostic] {
        let diagnosticEngine = RangeDiagnosticEngine()
        do {
            _ = try build(inputs: inputs, diagnosticEngine: diagnosticEngine)
        } catch {
            diagnosticEngine.emit(
                RangeDiagnosticConverter.diagnostic(
                    from: error,
                    path: fallbackPath ?? inputs.first(where: { !$0.role.isCore })?.path
                )
            )
        }
        return diagnosticEngine.diagnostics
    }

    private func parse(
        inputs: [SourceInput],
        literalBridgeResolver: LiteralBridgeResolver,
        declarationMemberResolver: DeclarationMemberResolver,
        declarationOperatorResolver: DeclarationOperatorResolver,
        declarationMacroExpansionResolver: DeclarationMacroExpansionResolver = .empty,
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration] = [:],
        macroExpansionTypes: [String: TypeReference] = [:]
    ) throws -> [ParsedSourceFile] {
        var currentMacrosByName = macroDeclarationsByName
        var currentMacroMetadataByName = macroMetadataDeclarationsByName
        var currentMacroExpansionResolver = declarationMacroExpansionResolver
        var currentMacroExpansionTypes = macroExpansionTypes
        var parsedFiles: [ParsedSourceFile] = []

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                literalBridgeResolver: literalBridgeResolver,
                declarationMemberResolver: declarationMemberResolver,
                declarationOperatorResolver: declarationOperatorResolver,
                declarationMacroExpansionResolver: currentMacroExpansionResolver,
                macroDeclarationsByName: currentMacrosByName,
                macroMetadataByName: currentMacroMetadataByName,
                macroExpansionTypes: currentMacroExpansionTypes
            )
            let sourceFile: ModuleFileNode
            do {
                sourceFile = try parser.parseSourceFile()
            } catch let error as ParseError {
                throw ParseError(input.path + ": " + error.message)
            } catch {
                throw ParseError(input.path + ": parse failed")
            }
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: sourceFile
            )

            parsedFiles.append(parsedFile)

            let discoveredMacros = MacroExpander.collectMacroDeclarations(from: [parsedFile])
            if !discoveredMacros.isEmpty {
                currentMacrosByName.merge(discoveredMacros) { _, new in new }
                currentMacroExpansionResolver = DeclarationMacroExpansionResolver(
                    macrosByName: currentMacrosByName
                )
                currentMacroExpansionTypes.merge(
                    MacroExpander.collectMacroExpansionTypes(from: [parsedFile])
                ) { _, new in new }
            }
            let discoveredMacroMetadata = MacroExpander.collectMacroMetadata(from: [parsedFile])
            if !discoveredMacroMetadata.isEmpty {
                currentMacroMetadataByName.merge(discoveredMacroMetadata) { _, new in new }
            }
        }

        return parsedFiles
    }

    private func discoverProjectDeclarationFiles(
        inputs: [SourceInput],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration] = [:]
    ) throws -> [ParsedSourceFile] {
        let discoveredMacrosByName = try discoverMacroDeclarations(
            inputs: inputs,
            macroDeclarationsByName: macroDeclarationsByName,
            macroMetadataDeclarationsByName: macroMetadataDeclarationsByName
        )
        let macrosByName = macroDeclarationsByName.merging(discoveredMacrosByName) {
            _, new in new
        }
        let discoveredMacroMetadataByName = try discoverMacroMetadataDeclarations(
            inputs: inputs,
            macroDeclarationsByName: macrosByName,
            macroMetadataDeclarationsByName: macroMetadataDeclarationsByName
        )
        let macroMetadataByName = macroMetadataDeclarationsByName.merging(discoveredMacroMetadataByName) {
            _, new in new
        }
        var parsedFiles: [ParsedSourceFile] = []

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                macroDeclarationsByName: macrosByName,
                macroMetadataByName: macroMetadataByName
            )
            let sourceFile: ModuleFileNode
            do {
                sourceFile = try parser.parseSourceFileForDeclarationDiscovery()
            } catch let error as ParseError {
                throw ParseError(input.path + ": " + error.message)
            } catch {
                throw ParseError(input.path + ": parse failed")
            }
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: sourceFile
            )
            parsedFiles.append(parsedFile)
        }

        return parsedFiles
    }

    private func discoverMacroDeclarations(
        inputs: [SourceInput],
        macroDeclarationsByName: [String: MacroDeclaration],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration]
    ) throws -> [String: MacroDeclaration] {
        var macrosByName = macroDeclarationsByName

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                macroDeclarationsByName: macrosByName,
                macroMetadataByName: macroMetadataDeclarationsByName
            )
            let sourceFile: ModuleFileNode
            do {
                sourceFile = try parser.parseSourceFileForDeclarationDiscovery()
            } catch let error as ParseError {
                throw ParseError(input.path + ": " + error.message)
            } catch {
                throw ParseError(input.path + ": parse failed")
            }
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: sourceFile
            )
            let discoveredMacros = MacroExpander.collectMacroDeclarations(from: [parsedFile])
            if !discoveredMacros.isEmpty {
                macrosByName.merge(discoveredMacros) { _, new in new }
            }
        }

        return macrosByName
    }

    private func discoverMacroMetadataDeclarations(
        inputs: [SourceInput],
        macroDeclarationsByName: [String: MacroDeclaration],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration]
    ) throws -> [String: MacroMetadataDeclaration] {
        var macroMetadataByName = macroMetadataDeclarationsByName

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                macroDeclarationsByName: macroDeclarationsByName,
                macroMetadataByName: macroMetadataDeclarationsByName
            )
            let sourceFile: ModuleFileNode
            do {
                sourceFile = try parser.parseSourceFileForDeclarationDiscovery()
            } catch let error as ParseError {
                throw ParseError(input.path + ": " + error.message)
            } catch {
                throw ParseError(input.path + ": parse failed")
            }
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: sourceFile
            )
            let discoveredMacroMetadata = MacroExpander.collectMacroMetadata(from: [parsedFile])
            if !discoveredMacroMetadata.isEmpty {
                macroMetadataByName.merge(discoveredMacroMetadata) { _, new in new }
            }
        }

        return macroMetadataByName
    }
}
