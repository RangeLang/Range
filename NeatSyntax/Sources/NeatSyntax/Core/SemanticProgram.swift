import Foundation

public enum SourceInputRole {
    case core
    case project
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

public struct SemanticProgram {
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

    public var programGraph: ProgramGraph {
        declarationGraph.programGraph
    }

    public var literalBridgeResolver: LiteralBridgeResolver {
        declarationViews.literalBridgeResolver
    }

    public var applicationGraph: ApplicationGraph {
        ApplicationGraphBuilder().build(program: self)
    }

    public var dependencyGraph: DependencyGraph {
        applicationGraph.dependencyGraph
    }

    public var projectParsedFiles: [ParsedSourceFile] {
        parsedFiles.filter { inputRoleByPath[$0.path] == .project }
    }

    public var projectExpandedFiles: [ParsedSourceFile] {
        expandedFiles.filter { inputRoleByPath[$0.path] == .project }
    }

    public func sourceRole(forPath path: String) -> SourceInputRole? {
        inputRoleByPath[path]
    }
}

public struct CompilerPipeline {
    public init() {}

    public func build(inputs: [SourceInput]) throws -> SemanticProgram {
        let orderedInputs = inputs.sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .core
            }
            return lhs.path < rhs.path
        }

        let coreInputs = orderedInputs.filter { $0.role == .core }
        let projectInputs = orderedInputs.filter { $0.role == .project }

        let parsedCoreFiles = try parse(
            inputs: coreInputs,
            literalBridgeResolver: .empty,
            declarationMemberResolver: .empty,
            declarationOperatorResolver: .empty
        )

        let coreMacrosByName = MacroExpander.collectMacros(from: parsedCoreFiles)
        let coreMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(from: parsedCoreFiles)
        let discoveredProjectDeclarationFiles = try discoverProjectDeclarationFiles(
            inputs: projectInputs
        )
        let discoveredProjectGraph = DeclarationGraph(
            files: parsedCoreFiles + discoveredProjectDeclarationFiles
        )
        let discoveredProjectViews = discoveredProjectGraph.views
        let discoveredProjectCallableReturnTypes = collectCallableReturnTypes(
            from: discoveredProjectDeclarationFiles
        )
        let discoveredProjectMacrosByName = MacroExpander.collectMacros(
            from: discoveredProjectDeclarationFiles
        )
        let discoveredProjectMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(
            from: discoveredProjectDeclarationFiles
        )
        let projectMacrosByName = coreMacrosByName.merging(discoveredProjectMacrosByName) { _, new in
            new
        }
        let parsedProjectFiles = try parse(
            inputs: projectInputs,
            literalBridgeResolver: discoveredProjectViews.literalBridgeResolver,
            declarationMemberResolver: discoveredProjectViews.memberResolver,
            declarationOperatorResolver: discoveredProjectViews.operatorResolver,
            declarationMacroExpansionResolver: DeclarationMacroExpansionResolver(
                macrosByName: projectMacrosByName
            ),
            discoveredCallableReturnTypes: discoveredProjectCallableReturnTypes,
            macroDeclarationsByName: projectMacrosByName,
            macroExpansionTypes: coreMacroExpansionTypes.merging(
                discoveredProjectMacroExpansionTypes
            ) { _, new in new }
        )

        let parsedFiles = parsedCoreFiles + parsedProjectFiles
        let expandedFiles = try MacroExpander.expand(files: parsedFiles)
        let declarationGraph = DeclarationGraph(files: expandedFiles)

        return SemanticProgram(
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            declarationGraph: declarationGraph
        )
    }

    public func buildValidated(inputs: [SourceInput]) throws -> SemanticProgram {
        let program = try build(inputs: inputs)
        try SemanticProgramValidator().validate(program)
        return program
    }

    public func validatePrimaryDeclarations(inputs: [SourceInput]) throws {
        let program = try build(inputs: inputs)
        try SemanticProgramValidator().validatePrimaryDeclarations(in: program)
    }

    private func parse(
        inputs: [SourceInput],
        literalBridgeResolver: LiteralBridgeResolver,
        declarationMemberResolver: DeclarationMemberResolver,
        declarationOperatorResolver: DeclarationOperatorResolver,
        declarationMacroExpansionResolver: DeclarationMacroExpansionResolver = .empty,
        discoveredCallableReturnTypes: [String: TypeReference] = [:],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        macroExpansionTypes: [String: TypeReference] = [:]
    ) throws -> [ParsedSourceFile] {
        var currentMacrosByName = macroDeclarationsByName
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
                discoveredCallableReturnTypes: discoveredCallableReturnTypes,
                macroDeclarationsByName: currentMacrosByName,
                macroExpansionTypes: currentMacroExpansionTypes
            )
            let parsedFile = ParsedSourceFile(
                path: input.path,
                sourceFile: try parser.parseSourceFile()
            )

            parsedFiles.append(parsedFile)

            let discoveredMacros = MacroExpander.collectMacros(from: [parsedFile])
            if !discoveredMacros.isEmpty {
                currentMacrosByName.merge(discoveredMacros) { _, new in new }
                currentMacroExpansionResolver = DeclarationMacroExpansionResolver(
                    macrosByName: currentMacrosByName
                )
                currentMacroExpansionTypes.merge(
                    MacroExpander.collectMacroExpansionTypes(from: [parsedFile])
                ) { _, new in new }
            }
        }

        return parsedFiles
    }

    private func discoverProjectDeclarationFiles(inputs: [SourceInput]) throws -> [ParsedSourceFile] {
        try inputs.map { input in
            var parser = try Parser(source: input.source)
            return ParsedSourceFile(
                path: input.path,
                sourceFile: try parser.parseSourceFileForDeclarationDiscovery()
            )
        }
    }

    private func collectCallableReturnTypes(
        from files: [ParsedSourceFile]
    ) -> [String: TypeReference] {
        var returnTypes: [String: TypeReference] = [:]

        for parsedFile in files {
            guard case .module(let module) = parsedFile.sourceFile else {
                continue
            }

            for callable in module.callables {
                guard let returnType = callable.returnType else {
                    continue
                }
                returnTypes[callable.name] = returnType
                if let targetType = callable.targetType {
                    returnTypes["\(targetType.displayName).\(callable.name)"] = returnType
                }
            }
        }

        return returnTypes
    }
}
