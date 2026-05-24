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
    public let runtimeHookResults: [CompilerPipelineRuntimeResult]

    private let inputRoleByPath: [String: SourceInputRole]

    public init(
        inputs: [SourceInput],
        parsedFiles: [ParsedSourceFile],
        expandedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph,
        runtimeHookResults: [CompilerPipelineRuntimeResult] = []
    ) {
        self.inputs = inputs
        self.parsedFiles = parsedFiles
        self.expandedFiles = expandedFiles
        self.declarationGraph = declarationGraph
        self.runtimeHookResults = runtimeHookResults
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
        diagnosticEngine: RangeDiagnosticEngine? = nil,
        runtimeHooks: [any CompilerPipelineRuntimeHook] = []
    ) throws -> CompiledProgram {
        let orderedInputs = inputs.sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .core
            }
            return lhs.path < rhs.path
        }

        let coreInputs = orderedInputs.filter { $0.role == .core }
        let projectInputs = orderedInputs.filter { $0.role == .project }
        var runtimeHookResults: [CompilerPipelineRuntimeResult] = []

        let discoveredCoreDeclarationFiles = try discoverProjectDeclarationFiles(
            inputs: coreInputs
        )
        try runRuntimeHooks(
            runtimeHooks,
            stage: .coreDeclarationsDiscovered,
            inputs: orderedInputs,
            parsedFiles: discoveredCoreDeclarationFiles,
            diagnosticEngine: diagnosticEngine,
            results: &runtimeHookResults
        )
        let discoveredCoreGraph = DeclarationGraph(files: discoveredCoreDeclarationFiles)
        let discoveredCoreViews = discoveredCoreGraph.views
        let discoveredCoreCallableReturnTypes = collectCallableReturnTypes(
            from: discoveredCoreDeclarationFiles
        )
        let discoveredCoreMacrosByName = MacroExpander.collectMacros(
            from: discoveredCoreDeclarationFiles
        )
        let discoveredCoreMarkersByName = MacroExpander.collectMarkers(
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
            discoveredCallableReturnTypes: discoveredCoreCallableReturnTypes,
            macroDeclarationsByName: discoveredCoreMacrosByName,
            markerDeclarationsByName: discoveredCoreMarkersByName,
            macroExpansionTypes: discoveredCoreMacroExpansionTypes
        )

        try runRuntimeHooks(
            runtimeHooks,
            stage: .coreParsed,
            inputs: orderedInputs,
            parsedFiles: parsedCoreFiles,
            diagnosticEngine: diagnosticEngine,
            results: &runtimeHookResults
        )

        let coreMacrosByName = MacroExpander.collectMacros(from: parsedCoreFiles)
        let coreMarkersByName = MacroExpander.collectMarkers(from: parsedCoreFiles)
        let coreMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(from: parsedCoreFiles)
        let discoveredProjectDeclarationFiles = try discoverProjectDeclarationFiles(
            inputs: projectInputs,
            macroDeclarationsByName: coreMacrosByName,
            markerDeclarationsByName: coreMarkersByName
        )
        try runRuntimeHooks(
            runtimeHooks,
            stage: .projectDeclarationsDiscovered,
            inputs: orderedInputs,
            parsedFiles: parsedCoreFiles + discoveredProjectDeclarationFiles,
            diagnosticEngine: diagnosticEngine,
            results: &runtimeHookResults
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
        let discoveredProjectMarkersByName = MacroExpander.collectMarkers(
            from: discoveredProjectDeclarationFiles
        )
        let discoveredProjectMacroExpansionTypes = MacroExpander.collectMacroExpansionTypes(
            from: discoveredProjectDeclarationFiles
        )
        let projectMacrosByName = coreMacrosByName.merging(discoveredProjectMacrosByName) { _, new in
            new
        }
        let projectMarkersByName = coreMarkersByName.merging(discoveredProjectMarkersByName) {
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
            discoveredCallableReturnTypes: discoveredProjectCallableReturnTypes,
            macroDeclarationsByName: projectMacrosByName,
            markerDeclarationsByName: projectMarkersByName,
            macroExpansionTypes: coreMacroExpansionTypes.merging(
                discoveredProjectMacroExpansionTypes
            ) { _, new in new }
        )

        let parsedFiles = parsedCoreFiles + parsedProjectFiles
        try runRuntimeHooks(
            runtimeHooks,
            stage: .projectParsed,
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            diagnosticEngine: diagnosticEngine,
            results: &runtimeHookResults
        )

        let expandedFiles = try MacroExpander.expand(
            files: parsedFiles,
            diagnosticEngine: diagnosticEngine
        )
        try runRuntimeHooks(
            runtimeHooks,
            stage: .macrosExpanded,
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            diagnosticEngine: diagnosticEngine,
            results: &runtimeHookResults
        )
        let declarationGraph = DeclarationGraph(files: expandedFiles)
        try runRuntimeHooks(
            runtimeHooks,
            stage: .declarationGraphBuilt,
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            declarationGraph: declarationGraph,
            diagnosticEngine: diagnosticEngine,
            results: &runtimeHookResults
        )

        return CompiledProgram(
            inputs: orderedInputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            declarationGraph: declarationGraph,
            runtimeHookResults: runtimeHookResults
        )
    }

    public func buildValidated(
        inputs: [SourceInput],
        diagnosticEngine: RangeDiagnosticEngine? = nil,
        runtimeHooks: [any CompilerPipelineRuntimeHook] = []
    ) throws -> CompiledProgram {
        let program = try build(
            inputs: inputs,
            diagnosticEngine: diagnosticEngine,
            runtimeHooks: runtimeHooks
        )
        try CompiledProgramValidator().validate(program)
        return program
    }

    public func diagnostics(inputs: [SourceInput], fallbackPath: String? = nil) -> [RangeDiagnostic] {
        let diagnosticEngine = RangeDiagnosticEngine()
        do {
            _ = try buildValidated(inputs: inputs, diagnosticEngine: diagnosticEngine)
        } catch {
            diagnosticEngine.emit(
                RangeDiagnosticConverter.diagnostic(
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


    private func runRuntimeHooks(
        _ hooks: [any CompilerPipelineRuntimeHook],
        stage: CompilerPipelineRuntimeStage,
        inputs: [SourceInput],
        parsedFiles: [ParsedSourceFile] = [],
        expandedFiles: [ParsedSourceFile] = [],
        declarationGraph: DeclarationGraph? = nil,
        diagnosticEngine: RangeDiagnosticEngine?,
        results: inout [CompilerPipelineRuntimeResult]
    ) throws {
        guard !hooks.isEmpty else { return }
        let context = CompilerPipelineRuntimeContext(
            stage: stage,
            inputs: inputs,
            parsedFiles: parsedFiles,
            expandedFiles: expandedFiles,
            declarationGraph: declarationGraph
        )

        for hook in hooks {
            guard let result = try hook.run(context: context) else {
                continue
            }
            results.append(result)
            for diagnostic in result.diagnostics {
                diagnosticEngine?.emit(diagnostic)
            }
        }
    }

    private func parse(
        inputs: [SourceInput],
        literalBridgeResolver: LiteralBridgeResolver,
        declarationMemberResolver: DeclarationMemberResolver,
        declarationOperatorResolver: DeclarationOperatorResolver,
        declarationMacroExpansionResolver: DeclarationMacroExpansionResolver = .empty,
        discoveredCallableReturnTypes: [String: TypeReference] = [:],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        markerDeclarationsByName: [String: MarkerDeclaration] = [:],
        macroExpansionTypes: [String: TypeReference] = [:]
    ) throws -> [ParsedSourceFile] {
        var currentMacrosByName = macroDeclarationsByName
        var currentMarkersByName = markerDeclarationsByName
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
                markerDeclarationsByName: currentMarkersByName,
                macroExpansionTypes: currentMacroExpansionTypes,
                allowInitializerDeclarations: false
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
            let discoveredMarkers = MacroExpander.collectMarkers(from: [parsedFile])
            if !discoveredMarkers.isEmpty {
                currentMarkersByName.merge(discoveredMarkers) { _, new in new }
            }
        }

        return parsedFiles
    }

    private func discoverProjectDeclarationFiles(
        inputs: [SourceInput],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        markerDeclarationsByName: [String: MarkerDeclaration] = [:]
    ) throws -> [ParsedSourceFile] {
        let discoveredMacrosByName = try discoverMacroDeclarations(
            inputs: inputs,
            macroDeclarationsByName: macroDeclarationsByName,
            markerDeclarationsByName: markerDeclarationsByName
        )
        let macrosByName = macroDeclarationsByName.merging(discoveredMacrosByName) {
            _, new in new
        }
        let discoveredMarkersByName = try discoverMarkerDeclarations(
            inputs: inputs,
            macroDeclarationsByName: macrosByName,
            markerDeclarationsByName: markerDeclarationsByName
        )
        let markersByName = markerDeclarationsByName.merging(discoveredMarkersByName) {
            _, new in new
        }
        var parsedFiles: [ParsedSourceFile] = []

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                macroDeclarationsByName: macrosByName,
                markerDeclarationsByName: markersByName,
                allowInitializerDeclarations: false
            )
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: try parser.parseSourceFileForDeclarationDiscovery()
            )
            parsedFiles.append(parsedFile)
        }

        return parsedFiles
    }

    private func discoverMacroDeclarations(
        inputs: [SourceInput],
        macroDeclarationsByName: [String: MacroDeclaration],
        markerDeclarationsByName: [String: MarkerDeclaration]
    ) throws -> [String: MacroDeclaration] {
        var macrosByName = macroDeclarationsByName

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                macroDeclarationsByName: macrosByName,
                markerDeclarationsByName: markerDeclarationsByName,
                allowInitializerDeclarations: false
            )
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: try parser.parseSourceFileForDeclarationDiscovery()
            )
            let discoveredMacros = MacroExpander.collectMacros(from: [parsedFile])
            if !discoveredMacros.isEmpty {
                macrosByName.merge(discoveredMacros) { _, new in new }
            }
        }

        return macrosByName
    }

    private func discoverMarkerDeclarations(
        inputs: [SourceInput],
        macroDeclarationsByName: [String: MacroDeclaration],
        markerDeclarationsByName: [String: MarkerDeclaration]
    ) throws -> [String: MarkerDeclaration] {
        var markersByName = markerDeclarationsByName

        for input in inputs {
            var parser = try Parser(
                source: input.source,
                macroDeclarationsByName: macroDeclarationsByName,
                markerDeclarationsByName: markersByName,
                allowInitializerDeclarations: false
            )
            let parsedFile = ParsedSourceFile(
                path: input.path,
                source: input.source,
                sourceFile: try parser.parseSourceFileForDeclarationDiscovery()
            )
            let discoveredMarkers = MacroExpander.collectMarkers(from: [parsedFile])
            if !discoveredMarkers.isEmpty {
                markersByName.merge(discoveredMarkers) { _, new in new }
            }
        }

        return markersByName
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
