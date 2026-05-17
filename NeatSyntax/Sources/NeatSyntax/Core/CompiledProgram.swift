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

    public var programGraph: ProgramGraph {
        declarationGraph.programGraph
    }

    public var literalBridgeResolver: LiteralBridgeResolver {
        declarationViews.literalBridgeResolver
    }

    public var applicationGraph: ApplicationGraph {
        ApplicationGraphBuilder().build(program: self)
    }

    public var graphProjections: [CompiledProgramGraphProjection] {
        CompiledProgramGraphFlow().deriveGraphs(from: self)
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

    public func build(
        inputs: [SourceInput],
        diagnosticEngine: NeatDiagnosticEngine? = nil
    ) throws -> CompiledProgram {
        let orderedInputs = inputs.sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .core
            }
            return lhs.path < rhs.path
        }

        let coreInputs = orderedInputs.filter { $0.role == .core }
        let projectInputs = orderedInputs.filter { $0.role == .project }

        let discoveredCoreDeclarationFiles = try discoverProjectDeclarationFiles(
            inputs: coreInputs
        )
        let discoveredCoreGraph = DeclarationGraph(files: discoveredCoreDeclarationFiles)
        let discoveredCoreViews = discoveredCoreGraph.views
        let discoveredCoreCallableReturnTypes = collectCallableReturnTypes(
            from: discoveredCoreDeclarationFiles
        )
        let parsedCoreFiles = try parse(
            inputs: coreInputs,
            literalBridgeResolver: discoveredCoreViews.literalBridgeResolver,
            declarationMemberResolver: discoveredCoreViews.memberResolver,
            declarationOperatorResolver: discoveredCoreViews.operatorResolver,
            discoveredCallableReturnTypes: discoveredCoreCallableReturnTypes
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

    public func buildValidated(
        inputs: [SourceInput],
        diagnosticEngine: NeatDiagnosticEngine? = nil
    ) throws -> CompiledProgram {
        let program = try build(inputs: inputs, diagnosticEngine: diagnosticEngine)
        try CompiledProgramValidator().validate(program)
        return program
    }

    public func diagnostics(inputs: [SourceInput], fallbackPath: String? = nil) -> [NeatDiagnostic] {
        let diagnosticEngine = NeatDiagnosticEngine()
        do {
            _ = try buildValidated(inputs: inputs, diagnosticEngine: diagnosticEngine)
        } catch {
            diagnosticEngine.emit(
                NeatDiagnosticConverter.diagnostic(
                    from: error,
                    path: fallbackPath ?? inputs.first(where: { $0.role == .project })?.path
                )
            )
        }
        return diagnosticEngine.diagnostics
    }

    public func validatePrimaryDeclarations(inputs: [SourceInput]) throws {
        let program = try build(inputs: inputs)
        try CompiledProgramValidator().validatePrimaryDeclarations(in: program)
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
                macroExpansionTypes: currentMacroExpansionTypes,
                allowInitializerDeclarations: input.role == .core
            )
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
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
            var parser = try Parser(
                source: input.source,
                allowInitializerDeclarations: input.role == .core
            )
            return ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: try parser.parseSourceFileForDeclarationDiscovery()
            )
        }
    }

    private func collectCallableReturnTypes(
        from files: [ParsedSourceFile]
    ) -> [String: TypeReference] {
        var returnTypes: [String: TypeReference] = [:]

        for parsedFile in files {
            collectCallableReturnTypes(
                from: parsedFile.sourceFile,
                into: &returnTypes
            )
        }

        return returnTypes
    }

    private func collectCallableReturnTypes(
        from sourceFile: SourceFileNode,
        into returnTypes: inout [String: TypeReference]
    ) {
        switch sourceFile {
        case .module(let module):
            for callable in module.callables {
                collectCallableReturnType(callable, into: &returnTypes)
            }
            for namespace in module.namespaces {
                collectCallableReturnTypes(
                    in: namespace,
                    qualifiedPrefix: namespace.name,
                    into: &returnTypes
                )
            }
            for declaration in module.extensions {
                collectCallableReturnTypes(
                    in: declaration,
                    qualifiedPrefix: declaration.targetName,
                    into: &returnTypes
                )
            }
        case .namespace(let namespace):
            collectCallableReturnTypes(
                in: namespace,
                qualifiedPrefix: namespace.name,
                into: &returnTypes
            )
        case .extensions(let declarations):
            for declaration in declarations {
                collectCallableReturnTypes(
                    in: declaration,
                    qualifiedPrefix: declaration.targetName,
                    into: &returnTypes
                )
            }
        default:
            break
        }
    }

    private func collectCallableReturnTypes(
        in namespace: NamespaceDeclaration,
        qualifiedPrefix: String,
        into returnTypes: inout [String: TypeReference]
    ) {
        for callable in namespace.callables {
            guard let returnType = callable.returnType else {
                continue
            }
            let qualifiedName = "\(qualifiedPrefix).\(callable.name)"
            returnTypes[qualifiedName] = returnType
            if let targetType = callable.targetType {
                returnTypes["\(targetType.displayName).\(qualifiedName)"] = returnType
            }
        }
        for nested in namespace.namespaces {
            collectCallableReturnTypes(
                in: nested,
                qualifiedPrefix: "\(qualifiedPrefix).\(nested.name)",
                into: &returnTypes
            )
        }
    }

    private func collectCallableReturnTypes(
        in declaration: ExtensionDeclaration,
        qualifiedPrefix: String,
        into returnTypes: inout [String: TypeReference]
    ) {
        for callable in declaration.callables {
            guard let returnType = callable.returnType else {
                continue
            }
            let qualifiedName = "\(qualifiedPrefix).\(callable.name)"
            returnTypes[qualifiedName] = returnType
            if let targetType = callable.targetType {
                returnTypes["\(targetType.displayName).\(qualifiedName)"] = returnType
            }
        }
        for namespace in declaration.namespaces {
            collectCallableReturnTypes(
                in: namespace,
                qualifiedPrefix: "\(qualifiedPrefix).\(namespace.name)",
                into: &returnTypes
            )
        }
    }

    private func collectCallableReturnType(
        _ callable: CallableDeclaration,
        into returnTypes: inout [String: TypeReference]
    ) {
        guard let returnType = callable.returnType else {
            return
        }
        returnTypes[callable.name] = returnType
        if let targetType = callable.targetType {
            returnTypes["\(targetType.displayName).\(callable.name)"] = returnType
        }
    }
}
