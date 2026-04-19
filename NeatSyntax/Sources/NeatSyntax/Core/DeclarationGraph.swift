import Foundation

public struct RealizedInitTarget: Hashable, Sendable {
    public let constructName: String
    public let parameterLabels: [String?]
    public let isCore: Bool

    public init(
        constructName: String,
        parameterLabels: [String?],
        isCore: Bool
    ) {
        self.constructName = constructName
        self.parameterLabels = parameterLabels
        self.isCore = isCore
    }
}

public struct RealizedLiteralBridge: Hashable, Sendable {
    public let initTarget: RealizedInitTarget
    public let carrierTypeName: String

    public init(
        initTarget: RealizedInitTarget,
        carrierTypeName: String,
    ) {
        self.initTarget = initTarget
        self.carrierTypeName = carrierTypeName
    }

    public var constructName: String {
        initTarget.constructName
    }

    public var parameterLabel: String? {
        guard initTarget.parameterLabels.count == 1 else {
            return nil
        }
        return initTarget.parameterLabels[0]
    }

    public var isCore: Bool {
        initTarget.isCore
    }
}

public struct RealizedInitMacroTarget {
    public let initTarget: RealizedInitTarget
    public let macros: [MacroApplication]

    public init(
        initTarget: RealizedInitTarget,
        macros: [MacroApplication]
    ) {
        self.initTarget = initTarget
        self.macros = macros
    }

    public var constructName: String {
        initTarget.constructName
    }

    public var parameterLabels: [String?] {
        initTarget.parameterLabels
    }

    public var isCore: Bool {
        initTarget.isCore
    }
}

public struct DeclarationGraph {
    public let protocolsByName: [String: ProtocolDeclaration]
    public let constructsByName: [String: ConstructDeclaration]
    public let enumsByName: [String: EnumDeclaration]
    public let macrosByName: [String: MacroDeclaration]
    public let extensionsByTargetName: [String: [ExtensionDeclaration]]
    public let topLevelStatesByFilePath: [String: [StateDeclaration]]
    public let statesByConstructName: [String: [StateDeclaration]]
    public let environmentsByConstructName: [String: [EnvironmentDeclaration]]
    public let bindingsByConstructName: [String: [BindingDeclaration]]
    public let derivedsByConstructName: [String: [DerivedDeclaration]]
    public let valuesByConstructName: [String: [ValueDeclaration]]
    public let initializersByConstructName: [String: [InitializerDeclaration]]
    public let parametersByCallableIdentity: [String: [NeatFunctionParameter]]
    public let parametersByInitializerIdentity: [String: [NeatFunctionParameter]]
    public let callablesByName: [String: [CallableDeclaration]]
    public let realizedLiteralBridges: [RealizedLiteralBridge]
    public let realizedInitMacroTargets: [RealizedInitMacroTarget]
    public let semanticGraph: SemanticGraph

    public init(files: [ParsedSourceFile]) {
        let protocols = Self.collectProtocols(from: files)
        let constructs = Self.collectConstructs(from: files, protocols: protocols)
        let enumerations = Self.collectEnums(from: files)
        let macros = Self.collectMacros(from: files)
        let extensions = Self.collectExtensions(from: files)
        let topLevelStates = Self.collectTopLevelStates(from: files)
        let statesByConstructName = Self.collectStatesByConstructName(from: constructs)
        let environmentsByConstructName = Self.collectEnvironmentsByConstructName(from: constructs)
        let bindingsByConstructName = Self.collectBindingsByConstructName(from: constructs)
        let derivedsByConstructName = Self.collectDerivedsByConstructName(from: constructs)
        let valuesByConstructName = Self.collectValuesByConstructName(from: constructs)
        let initializersByConstructName = Self.collectInitializersByConstructName(from: constructs)
        let callables = Self.collectCallables(from: files)
        let parametersByCallableIdentity = Self.collectParametersByCallableIdentity(from: files)
        let parametersByInitializerIdentity = Self.collectParametersByInitializerIdentity(
            from: constructs
        )

        self.protocolsByName = protocols
        self.constructsByName = constructs
        self.enumsByName = enumerations
        self.macrosByName = macros
        self.extensionsByTargetName = extensions
        self.topLevelStatesByFilePath = topLevelStates
        self.statesByConstructName = statesByConstructName
        self.environmentsByConstructName = environmentsByConstructName
        self.bindingsByConstructName = bindingsByConstructName
        self.derivedsByConstructName = derivedsByConstructName
        self.valuesByConstructName = valuesByConstructName
        self.initializersByConstructName = initializersByConstructName
        self.parametersByCallableIdentity = parametersByCallableIdentity
        self.parametersByInitializerIdentity = parametersByInitializerIdentity
        self.callablesByName = callables
        self.realizedLiteralBridges = Self.collectRealizedLiteralBridges(from: constructs)
        self.realizedInitMacroTargets = Self.collectRealizedInitMacroTargets(from: constructs)
        self.semanticGraph = Self.collectSemanticGraph(from: files)
    }

    public var views: DeclarationGraphViews {
        DeclarationGraphViews(
            literalBridgeResolver: LiteralBridgeResolver(realizedLiteralBridges: realizedLiteralBridges),
            memberResolver: DeclarationMemberResolver(constructsByName: constructsByName),
            operatorResolver: DeclarationOperatorResolver(callablesByName: callablesByName),
            registryView: DeclarationRegistryView(
                protocolsByName: protocolsByName,
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                macrosByName: macrosByName,
                extensionsByTargetName: extensionsByTargetName,
                topLevelStatesByFilePath: topLevelStatesByFilePath,
                statesByConstructName: statesByConstructName,
                environmentsByConstructName: environmentsByConstructName,
                bindingsByConstructName: bindingsByConstructName,
                derivedsByConstructName: derivedsByConstructName,
                valuesByConstructName: valuesByConstructName,
                initializersByConstructName: initializersByConstructName,
                parametersByCallableIdentity: parametersByCallableIdentity,
                parametersByInitializerIdentity: parametersByInitializerIdentity,
                callablesByName: callablesByName
            ),
            syntaxResolver: DeclarationSyntaxResolver(
                protocolsByName: protocolsByName,
                constructsByName: constructsByName
            )
        )
    }

    public var literalBridgeResolver: LiteralBridgeResolver {
        views.literalBridgeResolver
    }

    public var memberResolver: DeclarationMemberResolver {
        views.memberResolver
    }

    public var operatorResolver: DeclarationOperatorResolver {
        views.operatorResolver
    }

    public var syntaxResolver: DeclarationSyntaxResolver {
        views.syntaxResolver
    }

    public var registryView: DeclarationRegistryView {
        views.registryView
    }

    public var applicationDeclarationView: ApplicationDeclarationView {
        ApplicationDeclarationView(
            registryView: registryView,
            constructsByName: constructsByName
        )
    }

    public var programGraph: ProgramGraph {
        ProgramGraph(semanticGraph: semanticGraph)
    }

    static func collectProtocols(from files: [ParsedSourceFile]) -> [String: ProtocolDeclaration] {
        var registry: [String: ProtocolDeclaration] = [:]
        for parsedFile in files {
            for declaration in protocols(in: parsedFile.sourceFile) {
                registry[declaration.name] = declaration
            }
        }
        return registry
    }

    static func collectConstructs(
        from files: [ParsedSourceFile],
        protocols: [String: ProtocolDeclaration]
    ) -> [String: ConstructDeclaration] {
        var registry: [String: ConstructDeclaration] = [:]
        for parsedFile in files {
            for declaration in constructs(in: parsedFile.sourceFile) {
                collectConstruct(
                    declaration,
                    qualifiedName: declaration.name,
                    into: &registry,
                    protocols: protocols
                )
            }
        }
        return registry
    }

    static func collectEnums(from files: [ParsedSourceFile]) -> [String: EnumDeclaration] {
        var registry: [String: EnumDeclaration] = [:]
        for parsedFile in files {
            for declaration in enumerations(in: parsedFile.sourceFile) {
                registry[declaration.name] = declaration
            }
        }
        return registry
    }

    static func collectMacros(from files: [ParsedSourceFile]) -> [String: MacroDeclaration] {
        var registry: [String: MacroDeclaration] = [:]
        for parsedFile in files {
            for declaration in macros(in: parsedFile.sourceFile) {
                registry[declaration.name] = declaration
            }
        }
        return registry
    }

    static func collectExtensions(from files: [ParsedSourceFile]) -> [String: [ExtensionDeclaration]] {
        var registry: [String: [ExtensionDeclaration]] = [:]
        for parsedFile in files {
            for declaration in extensions(in: parsedFile.sourceFile) {
                registry[declaration.targetType.displayName, default: []].append(declaration)
            }
        }
        return registry
    }

    static func collectTopLevelStates(from files: [ParsedSourceFile]) -> [String: [StateDeclaration]] {
        var registry: [String: [StateDeclaration]] = [:]
        for parsedFile in files {
            registry[parsedFile.path] = topLevelStates(in: parsedFile.sourceFile)
        }
        return registry.filter { !$0.value.isEmpty }
    }

    static func collectStatesByConstructName(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [StateDeclaration]] {
        Dictionary(
            uniqueKeysWithValues: constructs.map { name, declaration in
                (name, declaration.states)
            }.filter { !$0.1.isEmpty }
        )
    }

    static func collectEnvironmentsByConstructName(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [EnvironmentDeclaration]] {
        Dictionary(
            uniqueKeysWithValues: constructs.map { name, declaration in
                (name, declaration.environments)
            }.filter { !$0.1.isEmpty }
        )
    }

    static func collectBindingsByConstructName(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [BindingDeclaration]] {
        Dictionary(
            uniqueKeysWithValues: constructs.map { name, declaration in
                (name, declaration.bindings)
            }.filter { !$0.1.isEmpty }
        )
    }

    static func collectDerivedsByConstructName(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [DerivedDeclaration]] {
        Dictionary(
            uniqueKeysWithValues: constructs.map { name, declaration in
                (name, declaration.deriveds)
            }.filter { !$0.1.isEmpty }
        )
    }

    static func collectValuesByConstructName(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [ValueDeclaration]] {
        Dictionary(
            uniqueKeysWithValues: constructs.map { name, declaration in
                (name, declaration.values)
            }.filter { !$0.1.isEmpty }
        )
    }

    static func collectInitializersByConstructName(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [InitializerDeclaration]] {
        Dictionary(
            uniqueKeysWithValues: constructs.map { name, declaration in
                (name, declaration.initializers)
            }.filter { !$0.1.isEmpty }
        )
    }

    static func collectParametersByCallableIdentity(
        from files: [ParsedSourceFile]
    ) -> [String: [NeatFunctionParameter]] {
        var registry: [String: [NeatFunctionParameter]] = [:]

        for parsedFile in files {
            switch parsedFile.sourceFile {
            case .module(let module):
                for callable in module.callables {
                    let identity = callableIdentity(
                        ownerName: nil,
                        declaration: callable
                    )
                    registry[identity] = callable.parameters
                }
                for construct in module.constructs {
                    collectCallableParameters(
                        in: construct,
                        registry: &registry,
                        ownerName: construct.name
                    )
                }
            case .construct(let construct):
                collectCallableParameters(
                    in: construct,
                    registry: &registry,
                    ownerName: construct.name
                )
            case .enumeration, .protocolDefinition, .macro, .mainBlock, .extensions:
                continue
            }
        }

        return registry
    }

    static func collectParametersByInitializerIdentity(
        from constructs: [String: ConstructDeclaration]
    ) -> [String: [NeatFunctionParameter]] {
        var registry: [String: [NeatFunctionParameter]] = [:]
        for (constructName, declaration) in constructs {
            for initializer in declaration.initializers {
                registry[initializerIdentity(
                    constructName: constructName,
                    declaration: initializer
                )] = initializer.parameters
            }
        }
        return registry
    }

    private static func collectConstruct(
        _ declaration: ConstructDeclaration,
        qualifiedName: String,
        into registry: inout [String: ConstructDeclaration],
        protocols: [String: ProtocolDeclaration]
    ) {
        let realizedInitializers = carriedProtocolInitializerMacros(
            for: declaration.initializers,
            conformances: declaration.conformances,
            protocols: protocols
        )

        let qualifiedChildren = declaration.constructs.map { child in
            qualifiedConstruct(child, qualifiedName: "\(qualifiedName).\(child.name)")
        }

        registry[qualifiedName] = ConstructDeclaration(
            macros: declaration.macros,
            kind: declaration.kind,
            attribute: declaration.attribute,
            name: qualifiedName,
            genericParameters: declaration.genericParameters,
            conformances: declaration.conformances,
            states: declaration.states,
            environments: declaration.environments,
            bindings: declaration.bindings,
            deriveds: declaration.deriveds,
            values: declaration.values,
            initializers: realizedInitializers,
            callables: declaration.callables,
            constructs: qualifiedChildren
        )

        for child in declaration.constructs {
            collectConstruct(
                child,
                qualifiedName: "\(qualifiedName).\(child.name)",
                into: &registry,
                protocols: protocols
            )
        }
    }

    private static func qualifiedConstruct(
        _ declaration: ConstructDeclaration,
        qualifiedName: String
    ) -> ConstructDeclaration {
        ConstructDeclaration(
            macros: declaration.macros,
            kind: declaration.kind,
            attribute: declaration.attribute,
            name: qualifiedName,
            genericParameters: declaration.genericParameters,
            conformances: declaration.conformances,
            states: declaration.states,
            environments: declaration.environments,
            bindings: declaration.bindings,
            deriveds: declaration.deriveds,
            values: declaration.values,
            initializers: declaration.initializers,
            callables: declaration.callables,
            constructs: declaration.constructs.map {
                qualifiedConstruct($0, qualifiedName: "\(qualifiedName).\($0.name)")
            }
        )
    }

    static func collectCallables(from files: [ParsedSourceFile]) -> [String: [CallableDeclaration]]
    {
        var registry: [String: [CallableDeclaration]] = [:]
        for parsedFile in files {
            for declaration in callables(in: parsedFile.sourceFile) {
                registry[declaration.name, default: []].append(declaration)
            }
        }
        return registry
    }

    static func collectRealizedLiteralBridges(
        from constructs: [String: ConstructDeclaration]
    ) -> [RealizedLiteralBridge] {
        constructs.values.flatMap { construct in
            construct.initializers.compactMap { initializer in
                guard initializer.parameters.count == 1 else {
                    return nil
                }

                guard
                    let literalMacro = initializer.macros.first(where: { $0.name == "literal" }),
                    literalMacro.genericArguments.count == 1
                else {
                    return nil
                }

                return RealizedLiteralBridge(
                    initTarget: RealizedInitTarget(
                        constructName: construct.name,
                        parameterLabels: initializer.parameters.map(\.externalLabel),
                        isCore: construct.isCore
                    ),
                    carrierTypeName: literalMacro.genericArguments[0].displayName
                )
            }
        }
    }

    static func collectRealizedInitMacroTargets(
        from constructs: [String: ConstructDeclaration]
    ) -> [RealizedInitMacroTarget] {
        constructs.values.flatMap { construct in
            construct.initializers.compactMap { initializer in
                guard !initializer.macros.isEmpty else {
                    return nil
                }

                return RealizedInitMacroTarget(
                    initTarget: RealizedInitTarget(
                        constructName: construct.name,
                        parameterLabels: initializer.parameters.map(\.externalLabel),
                        isCore: construct.isCore
                    ),
                    macros: initializer.macros
                )
            }
        }
    }

    static func protocols(in sourceFile: SourceFileNode) -> [ProtocolDeclaration] {
        switch sourceFile {
        case .protocolDefinition(let declaration):
            return [declaration]
        case .module(let module):
            return module.protocols
        case .construct, .enumeration, .mainBlock, .macro, .extensions:
            return []
        }
    }

    static func constructs(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    static func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .enumeration, .protocolDefinition, .macro, .mainBlock, .extensions:
            return []
        }
    }

    static func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let declaration):
            return [declaration]
        case .module(let module):
            return module.enumerations
        case .construct, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .enumeration, .mainBlock, .protocolDefinition, .extensions:
            return []
        }
    }

    static func extensions(in sourceFile: SourceFileNode) -> [ExtensionDeclaration] {
        switch sourceFile {
        case .extensions(let declarations):
            return declarations
        case .module(let module):
            return module.extensions
        case .construct, .enumeration, .mainBlock, .macro, .protocolDefinition:
            return []
        }
    }

    static func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables
        case .construct, .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    private static func collectCallableParameters(
        in construct: ConstructDeclaration,
        registry: inout [String: [NeatFunctionParameter]],
        ownerName: String
    ) {
        for callable in construct.callables {
            registry[callableIdentity(ownerName: ownerName, declaration: callable)] =
                callable.parameters
        }

        for child in construct.constructs {
            let childOwnerName = "\(ownerName).\(child.name)"
            collectCallableParameters(
                in: child,
                registry: &registry,
                ownerName: childOwnerName
            )
        }
    }

    static func callableIdentity(
        ownerName: String?,
        declaration: CallableDeclaration
    ) -> String {
        let owner = ownerName ?? "<top-level>"
        return "\(owner)::\(declaration.name)(\(renderParameterList(declaration.parameters)))"
    }

    static func initializerIdentity(
        constructName: String,
        declaration: InitializerDeclaration
    ) -> String {
        "\(constructName)::init(\(renderParameterList(declaration.parameters)))"
    }

    static func renderParameterList(_ parameters: [NeatFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
                ?? "_"
            let label = parameter.externalLabel ?? "_"
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }

    static func carriedProtocolInitializerMacros(
        for initializers: [InitializerDeclaration],
        conformances: [TypeReference],
        protocols: [String: ProtocolDeclaration]
    ) -> [InitializerDeclaration] {
        let requirementInitializers = conformances.compactMap { protocols[$0.displayName] }
            .flatMap(\.initializers)

        guard !requirementInitializers.isEmpty else {
            return initializers
        }

        return initializers.map { initializer in
            let carried =
                requirementInitializers
                .filter { requirement in
                    carriedInitializerSignatureMatches(lhs: requirement, rhs: initializer)
                }
                .flatMap(\.macros)

            guard !carried.isEmpty else {
                return initializer
            }

            let mergedMacros =
                initializer.macros
                + carried.filter { carriedMacro in
                    !initializer.macros.contains {
                        $0.name == carriedMacro.name
                            && $0.genericArguments == carriedMacro.genericArguments
                            && $0.argumentClause == carriedMacro.argumentClause
                    }
                }

            return InitializerDeclaration(
                macros: mergedMacros,
                parameters: initializer.parameters,
                body: initializer.body
            )
        }
    }

    static func carriedInitializerSignatureMatches(
        lhs: InitializerDeclaration,
        rhs: InitializerDeclaration
    ) -> Bool {
        lhs.parameters.elementsEqual(
            rhs.parameters,
            by: {
                $0.localName == $1.localName
                    && $0.externalLabel == $1.externalLabel
                    && $0.typeReference == $1.typeReference
                    && $0.slotName == $1.slotName
                    && $0.isBinding == $1.isBinding
            })
    }

    static func collectSemanticGraph(from files: [ParsedSourceFile]) -> SemanticGraph {
        var collector = SemanticGraphCollector()
        for parsedFile in files.sorted(by: { $0.path < $1.path }) {
            collector.add(parsedFile)
        }
        return collector.build()
    }
}

private struct SemanticGraphCollector {
    private var entitiesByID: [String: SemanticGraphEntity] = [:]
    private var relations: Set<SemanticGraphRelation> = []

    mutating func build() -> SemanticGraph {
        SemanticGraph(
            entities: Array(entitiesByID.values),
            relations: Array(relations)
        )
    }

    mutating func add(_ parsedFile: ParsedSourceFile) {
        let fileID = "file:\(parsedFile.path)"
        let fileLabel = URL(fileURLWithPath: parsedFile.path).lastPathComponent
        addEntity(id: fileID, kind: .file, label: fileLabel)

        switch parsedFile.sourceFile {
        case .construct(let declaration):
            addConstruct(declaration, parentID: fileID)
        case .enumeration(let declaration):
            addEnumeration(declaration, parentID: fileID)
        case .protocolDefinition(let declaration):
            addProtocol(declaration, parentID: fileID)
        case .macro(let declaration):
            addMacroDeclaration(declaration, parentID: fileID)
        case .extensions(let declarations):
            for declaration in declarations {
                addExtension(declaration, parentID: fileID)
            }
        case .module(let module):
            if module.mainBlock != nil {
                let mainID = "\(fileID)/main"
                addEntity(id: mainID, kind: .mainBlock, label: "@main")
                addRelation(from: fileID, to: mainID, kind: .contains)
            }
            for state in module.states {
                addState(state, parentID: fileID)
            }
            for callable in module.callables {
                addCallable(callable, parentID: fileID)
            }
            for declaration in module.constructs {
                addConstruct(declaration, parentID: fileID)
            }
            for declaration in module.enumerations {
                addEnumeration(declaration, parentID: fileID)
            }
            for declaration in module.protocols {
                addProtocol(declaration, parentID: fileID)
            }
            for declaration in module.macros {
                addMacroDeclaration(declaration, parentID: fileID)
            }
            for declaration in module.extensions {
                addExtension(declaration, parentID: fileID)
            }
        case .mainBlock:
            let mainID = "\(fileID)/main"
            addEntity(id: mainID, kind: .mainBlock, label: "@main")
            addRelation(from: fileID, to: mainID, kind: .contains)
        }
    }

    private mutating func addConstruct(_ declaration: ConstructDeclaration, parentID: String) {
        let constructID = "\(parentID)/construct:\(declaration.name)"
        let label = declaration.isCore ? "@core \(declaration.name)" : declaration.name
        addEntity(id: constructID, kind: .construct, label: label)
        addRelation(from: parentID, to: constructID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: constructID)
        addTypeReferences(declaration.conformances, from: constructID, kind: .conformsTo)

        for state in declaration.states {
            addState(state, parentID: constructID)
        }
        for environment in declaration.environments {
            addEnvironment(environment, parentID: constructID)
        }
        for binding in declaration.bindings {
            addBinding(binding, parentID: constructID)
        }
        for derived in declaration.deriveds {
            addDerived(derived, parentID: constructID)
        }
        for value in declaration.values {
            addValue(value, parentID: constructID)
        }
        for initializer in declaration.initializers {
            addInitializer(initializer, parentID: constructID)
        }
        for callable in declaration.callables {
            addCallable(callable, parentID: constructID)
        }
        for nested in declaration.constructs {
            addConstruct(nested, parentID: constructID)
        }
    }

    private mutating func addEnumeration(_ declaration: EnumDeclaration, parentID: String) {
        let enumID = "\(parentID)/enum:\(declaration.name)"
        addEntity(id: enumID, kind: .enumeration, label: declaration.name)
        addRelation(from: parentID, to: enumID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: enumID)
        addTypeReferences(declaration.conformances, from: enumID, kind: .conformsTo)
    }

    private mutating func addProtocol(_ declaration: ProtocolDeclaration, parentID: String) {
        let protocolID = "\(parentID)/protocol:\(declaration.name)"
        let label = declaration.isCore ? "@core \(declaration.name)" : declaration.name
        addEntity(id: protocolID, kind: .protocolDefinition, label: label)
        addRelation(from: parentID, to: protocolID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: protocolID)
        addTypeReferences(declaration.conformances, from: protocolID, kind: .conformsTo)
    }

    private mutating func addMacroDeclaration(_ declaration: MacroDeclaration, parentID: String) {
        let macroID = "\(parentID)/macro:\(declaration.name)"
        addEntity(id: macroID, kind: .macro, label: declaration.name)
        addRelation(from: parentID, to: macroID, kind: .contains)
        addTypeReference(declaration.target.typeReference, from: macroID, kind: .targetsMacro)
    }

    private mutating func addExtension(_ declaration: ExtensionDeclaration, parentID: String) {
        let extensionID = "\(parentID)/extension:\(declaration.targetType.displayName)"
        addEntity(id: extensionID, kind: .typeExtension, label: declaration.targetType.displayName)
        addRelation(from: parentID, to: extensionID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: extensionID)
        addTypeReference(declaration.targetType, from: extensionID, kind: .extends)
    }

    private mutating func addState(_ declaration: StateDeclaration, parentID: String) {
        let stateID = "\(parentID)/state:\(declaration.name)"
        addEntity(id: stateID, kind: .state, label: declaration.name)
        addRelation(from: parentID, to: stateID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: stateID)
        addStorageTypeReference(declaration.type, from: stateID)
    }

    private mutating func addEnvironment(_ declaration: EnvironmentDeclaration, parentID: String) {
        let environmentID = "\(parentID)/environment:\(declaration.name)"
        addEntity(id: environmentID, kind: .environment, label: declaration.name)
        addRelation(from: parentID, to: environmentID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: environmentID)
        addStorageTypeReference(.named(declaration.typeName), from: environmentID)
    }

    private mutating func addBinding(_ declaration: BindingDeclaration, parentID: String) {
        let bindingID = "\(parentID)/binding:\(declaration.name)"
        addEntity(id: bindingID, kind: .binding, label: declaration.name)
        addRelation(from: parentID, to: bindingID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: bindingID)
        addStorageTypeReference(.named(declaration.typeName), from: bindingID)
    }

    private mutating func addDerived(_ declaration: DerivedDeclaration, parentID: String) {
        let derivedID = "\(parentID)/derived:\(declaration.name)"
        addEntity(id: derivedID, kind: .derived, label: declaration.name)
        addRelation(from: parentID, to: derivedID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: derivedID)
        addStorageTypeReference(.named(declaration.typeName), from: derivedID)
        if let builderName = declaration.builderName {
            addTypeReference(.named(builderName), from: derivedID, kind: .referencesType)
        }
    }

    private mutating func addValue(_ declaration: ValueDeclaration, parentID: String) {
        let valueID = "\(parentID)/value:\(declaration.name)"
        addEntity(id: valueID, kind: .value, label: declaration.name)
        addRelation(from: parentID, to: valueID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: valueID)
        addStorageTypeReference(.named(declaration.typeName), from: valueID)
    }

    private mutating func addInitializer(_ declaration: InitializerDeclaration, parentID: String) {
        let initializerID = "\(parentID)/init:\(renderParameterList(declaration.parameters))"
        addEntity(id: initializerID, kind: .initializer, label: "init")
        addRelation(from: parentID, to: initializerID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: initializerID)
        for parameter in declaration.parameters {
            addParameter(parameter, parentID: initializerID)
        }
    }

    private mutating func addCallable(_ declaration: CallableDeclaration, parentID: String) {
        let callableID =
            "\(parentID)/function:\(declaration.name)(\(renderParameterList(declaration.parameters)))"
        addEntity(id: callableID, kind: .function, label: declaration.name)
        addRelation(from: parentID, to: callableID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: callableID)
        if let targetType = declaration.targetType {
            addTypeReference(targetType, from: callableID, kind: .referencesType)
        }
        if let returnType = declaration.returnType {
            addTypeReference(returnType, from: callableID, kind: .referencesType)
        }
        for parameter in declaration.parameters {
            addParameter(parameter, parentID: callableID)
        }
    }

    private mutating func addParameter(_ parameter: NeatFunctionParameter, parentID: String) {
        let label = parameter.externalLabel ?? "_"
        let parameterID = "\(parentID)/parameter:\(label):\(parameter.localName)"
        addEntity(id: parameterID, kind: .parameter, label: parameter.localName)
        addRelation(from: parentID, to: parameterID, kind: .contains)
        addMacroApplications(parameter.macros, parentID: parameterID)
        if let typeReference = parameter.typeReference {
            addStorageTypeReference(typeReference, from: parameterID)
        }
    }

    private mutating func addStorageTypeReference(_ reference: TypeReference, from sourceID: String) {
        addTypeReference(reference, from: sourceID, kind: .referencesType)
    }

    private mutating func addMacroApplications(_ macros: [MacroApplication], parentID: String) {
        for macro in macros {
            let macroID = "\(parentID)/macro-application:#\(macro.name)"
            addEntity(id: macroID, kind: .macroApplication, label: "#\(macro.name)")
            addRelation(from: parentID, to: macroID, kind: .appliesMacro)
        }
    }

    private mutating func addTypeReferences(
        _ references: [TypeReference],
        from sourceID: String,
        kind: SemanticGraphRelationKind
    ) {
        for reference in references {
            addTypeReference(reference, from: sourceID, kind: kind)
        }
    }

    private mutating func addTypeReference(
        _ reference: TypeReference,
        from sourceID: String,
        kind: SemanticGraphRelationKind
    ) {
        let typeID = "type:\(reference.displayName)"
        addEntity(id: typeID, kind: .typeReference, label: reference.displayName)
        addRelation(from: sourceID, to: typeID, kind: kind)
    }

    private mutating func addEntity(
        id: String,
        kind: SemanticGraphEntityKind,
        label: String
    ) {
        entitiesByID[id] = SemanticGraphEntity(id: id, kind: kind, label: label)
    }

    private mutating func addRelation(
        from sourceID: String,
        to targetID: String,
        kind: SemanticGraphRelationKind
    ) {
        relations.insert(SemanticGraphRelation(sourceID: sourceID, targetID: targetID, kind: kind))
    }

    private func renderParameterList(_ parameters: [NeatFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
                ?? "_"
            let label = parameter.externalLabel ?? "_"
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }
}

public struct DeclarationGraphViews {
    public let literalBridgeResolver: LiteralBridgeResolver
    public let memberResolver: DeclarationMemberResolver
    public let operatorResolver: DeclarationOperatorResolver
    public let registryView: DeclarationRegistryView
    public let syntaxResolver: DeclarationSyntaxResolver

    public init(
        literalBridgeResolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        registryView: DeclarationRegistryView,
        syntaxResolver: DeclarationSyntaxResolver
    ) {
        self.literalBridgeResolver = literalBridgeResolver
        self.memberResolver = memberResolver
        self.operatorResolver = operatorResolver
        self.registryView = registryView
        self.syntaxResolver = syntaxResolver
    }
}

public struct DeclarationRegistryView {
    private let protocolsByName: [String: ProtocolDeclaration]
    private let constructsByName: [String: ConstructDeclaration]
    private let enumsByName: [String: EnumDeclaration]
    private let macrosByName: [String: MacroDeclaration]
    private let extensionsByTargetName: [String: [ExtensionDeclaration]]
    private let topLevelStatesByFilePath: [String: [StateDeclaration]]
    private let statesByConstructName: [String: [StateDeclaration]]
    private let environmentsByConstructName: [String: [EnvironmentDeclaration]]
    private let bindingsByConstructName: [String: [BindingDeclaration]]
    private let derivedsByConstructName: [String: [DerivedDeclaration]]
    private let valuesByConstructName: [String: [ValueDeclaration]]
    private let initializersByConstructName: [String: [InitializerDeclaration]]
    private let parametersByCallableIdentity: [String: [NeatFunctionParameter]]
    private let parametersByInitializerIdentity: [String: [NeatFunctionParameter]]
    private let callablesByName: [String: [CallableDeclaration]]

    public init(
        protocolsByName: [String: ProtocolDeclaration],
        constructsByName: [String: ConstructDeclaration],
        enumsByName: [String: EnumDeclaration],
        macrosByName: [String: MacroDeclaration],
        extensionsByTargetName: [String: [ExtensionDeclaration]],
        topLevelStatesByFilePath: [String: [StateDeclaration]],
        statesByConstructName: [String: [StateDeclaration]],
        environmentsByConstructName: [String: [EnvironmentDeclaration]],
        bindingsByConstructName: [String: [BindingDeclaration]],
        derivedsByConstructName: [String: [DerivedDeclaration]],
        valuesByConstructName: [String: [ValueDeclaration]],
        initializersByConstructName: [String: [InitializerDeclaration]],
        parametersByCallableIdentity: [String: [NeatFunctionParameter]],
        parametersByInitializerIdentity: [String: [NeatFunctionParameter]],
        callablesByName: [String: [CallableDeclaration]]
    ) {
        self.protocolsByName = protocolsByName
        self.constructsByName = constructsByName
        self.enumsByName = enumsByName
        self.macrosByName = macrosByName
        self.extensionsByTargetName = extensionsByTargetName
        self.topLevelStatesByFilePath = topLevelStatesByFilePath
        self.statesByConstructName = statesByConstructName
        self.environmentsByConstructName = environmentsByConstructName
        self.bindingsByConstructName = bindingsByConstructName
        self.derivedsByConstructName = derivedsByConstructName
        self.valuesByConstructName = valuesByConstructName
        self.initializersByConstructName = initializersByConstructName
        self.parametersByCallableIdentity = parametersByCallableIdentity
        self.parametersByInitializerIdentity = parametersByInitializerIdentity
        self.callablesByName = callablesByName
    }

    public var allConstructsByName: [String: ConstructDeclaration] {
        constructsByName
    }

    public func `protocol`(named name: String) -> ProtocolDeclaration? {
        protocolsByName[name]
    }

    public func construct(named name: String) -> ConstructDeclaration? {
        constructsByName[name]
    }

    public func enumeration(named name: String) -> EnumDeclaration? {
        enumsByName[name]
    }

    public func macro(named name: String) -> MacroDeclaration? {
        macrosByName[name]
    }

    public func extensions(targeting targetName: String) -> [ExtensionDeclaration] {
        extensionsByTargetName[targetName, default: []]
    }

    public func topLevelStates(inFilePath path: String) -> [StateDeclaration] {
        topLevelStatesByFilePath[path, default: []]
    }

    public func states(onConstruct named: String) -> [StateDeclaration] {
        statesByConstructName[named, default: []]
    }

    public func environments(onConstruct named: String) -> [EnvironmentDeclaration] {
        environmentsByConstructName[named, default: []]
    }

    public func bindings(onConstruct named: String) -> [BindingDeclaration] {
        bindingsByConstructName[named, default: []]
    }

    public func deriveds(onConstruct named: String) -> [DerivedDeclaration] {
        derivedsByConstructName[named, default: []]
    }

    public func values(onConstruct named: String) -> [ValueDeclaration] {
        valuesByConstructName[named, default: []]
    }

    public func initializers(onConstruct named: String) -> [InitializerDeclaration] {
        initializersByConstructName[named, default: []]
    }

    public func callables(named name: String) -> [CallableDeclaration] {
        callablesByName[name, default: []]
    }

    public func callableIdentity(
        ownerName: String?,
        declaration: CallableDeclaration
    ) -> String {
        DeclarationGraph.callableIdentity(ownerName: ownerName, declaration: declaration)
    }

    public func initializerIdentity(
        constructName: String,
        declaration: InitializerDeclaration
    ) -> String {
        DeclarationGraph.initializerIdentity(
            constructName: constructName,
            declaration: declaration
        )
    }

    public func parameters(
        ofCallable declaration: CallableDeclaration,
        ownerName: String?
    ) -> [NeatFunctionParameter] {
        parametersByCallableIdentity[
            callableIdentity(ownerName: ownerName, declaration: declaration),
            default: []
        ]
    }

    public func parameters(
        ofInitializer declaration: InitializerDeclaration,
        constructName: String
    ) -> [NeatFunctionParameter] {
        parametersByInitializerIdentity[
            initializerIdentity(constructName: constructName, declaration: declaration),
            default: []
        ]
    }

    public func hasProtocol(named name: String) -> Bool {
        protocolsByName[name] != nil
    }

    public func hasConstruct(named name: String) -> Bool {
        constructsByName[name] != nil
    }

    public func hasEnumeration(named name: String) -> Bool {
        enumsByName[name] != nil
    }

    public func hasMacro(named name: String) -> Bool {
        macrosByName[name] != nil
    }

    public func hasExtensions(targeting targetName: String) -> Bool {
        !(extensionsByTargetName[targetName] ?? []).isEmpty
    }

    public func hasTopLevelStates(inFilePath path: String) -> Bool {
        !(topLevelStatesByFilePath[path] ?? []).isEmpty
    }

    public func hasStates(onConstruct named: String) -> Bool {
        !(statesByConstructName[named] ?? []).isEmpty
    }

    public func hasEnvironments(onConstruct named: String) -> Bool {
        !(environmentsByConstructName[named] ?? []).isEmpty
    }

    public func hasBindings(onConstruct named: String) -> Bool {
        !(bindingsByConstructName[named] ?? []).isEmpty
    }

    public func hasDeriveds(onConstruct named: String) -> Bool {
        !(derivedsByConstructName[named] ?? []).isEmpty
    }

    public func hasValues(onConstruct named: String) -> Bool {
        !(valuesByConstructName[named] ?? []).isEmpty
    }

    public func hasInitializers(onConstruct named: String) -> Bool {
        !(initializersByConstructName[named] ?? []).isEmpty
    }
}

public struct ApplicationDeclarationView {
    private let registryView: DeclarationRegistryView
    private let constructsByName: [String: ConstructDeclaration]

    public init(
        registryView: DeclarationRegistryView,
        constructsByName: [String: ConstructDeclaration]
    ) {
        self.registryView = registryView
        self.constructsByName = constructsByName
    }

    public func topLevelStates(inFilePath path: String) -> [StateDeclaration] {
        registryView.topLevelStates(inFilePath: path)
    }

    public func construct(named name: String) -> ConstructDeclaration? {
        constructsByName[name]
    }

    public func hasConstruct(named name: String) -> Bool {
        constructsByName[name] != nil
    }

    public func isCoreConstruct(named name: String) -> Bool {
        constructsByName[name]?.isCore == true
    }

    public func callable(
        named callableName: String,
        onConstruct named: String
    ) -> CallableDeclaration? {
        constructsByName[named]?.callables.first(where: { $0.name == callableName })
    }

    public func memberKinds(
        forConstruct named: String
    ) -> [String: ApplicationGraphNodeKind] {
        guard let declaration = constructsByName[named] else {
            return [:]
        }

        var result: [String: ApplicationGraphNodeKind] = [:]
        for state in declaration.states { result[state.name] = .state }
        for environment in declaration.environments { result[environment.name] = .environment }
        for binding in declaration.bindings { result[binding.name] = .binding }
        for derived in declaration.deriveds { result[derived.name] = .derived }
        for value in declaration.values { result[value.name] = .value }
        return result
    }

    public func constructTypedMemberNames(
        forConstruct named: String
    ) -> [String: String] {
        guard let declaration = constructsByName[named] else {
            return [:]
        }

        var result: [String: String] = [:]
        for binding in declaration.bindings where hasConstruct(named: binding.typeName) {
            result[binding.name] = binding.typeName
        }
        for value in declaration.values where hasConstruct(named: value.typeName) {
            result[value.name] = value.typeName
        }
        return result
    }
}

public struct DeclarationSyntaxResolver {
    private let protocolsByName: [String: ProtocolDeclaration]
    private let constructsByName: [String: ConstructDeclaration]

    public init(
        protocolsByName: [String: ProtocolDeclaration],
        constructsByName: [String: ConstructDeclaration]
    ) {
        self.protocolsByName = protocolsByName
        self.constructsByName = constructsByName
    }

    public func typeConformsToSyntax(_ typeReference: TypeReference?) -> Bool {
        typeConforms(typeReference, to: "Syntax")
    }

    public func typeConforms(_ typeReference: TypeReference?, to targetProtocol: String) -> Bool {
        guard let typeName = nominalName(of: typeReference) else {
            return false
        }
        return declaration(named: typeName, conformsTo: targetProtocol)
    }

    public func declaration(
        named name: String,
        conformsTo targetProtocol: String
    ) -> Bool {
        declaration(
            named: name,
            conformsTo: targetProtocol,
            visited: []
        )
    }

    private func declaration(
        named name: String,
        conformsTo targetProtocol: String,
        visited: Set<String>
    ) -> Bool {
        if name == targetProtocol {
            return true
        }
        if visited.contains(name) {
            return false
        }
        var nextVisited = visited
        nextVisited.insert(name)

        if let protocolDeclaration = protocolsByName[name] {
            return protocolDeclaration.conformances.contains {
                conformance in
                guard let conformanceName = nominalName(of: conformance) else {
                    return false
                }
                return declaration(
                    named: conformanceName,
                    conformsTo: targetProtocol,
                    visited: nextVisited
                )
            }
        }

        if let constructDeclaration = constructsByName[name] {
            return constructDeclaration.conformances.contains {
                conformance in
                guard let conformanceName = nominalName(of: conformance) else {
                    return false
                }
                return declaration(
                    named: conformanceName,
                    conformsTo: targetProtocol,
                    visited: nextVisited
                )
            }
        }

        return false
    }

    public func nominalName(of typeReference: TypeReference?) -> String? {
        guard let typeReference else {
            return nil
        }
        switch typeReference {
        case .named(let name):
            return name
        case .generic(let base, _):
            return nominalName(of: base)
        case .member:
            return typeReference.displayName
        case .array, .function, .optional, .variadic:
            return nil
        }
    }
}

public struct DeclarationMacroExpansionArgument: Sendable {
    public let label: String?
    public let type: BootstrapLiteralType?

    public init(label: String?, type: BootstrapLiteralType?) {
        self.label = label
        self.type = type
    }
}

public struct DeclarationMacroExpansionResolver: Sendable {
    public static let empty = DeclarationMacroExpansionResolver(macrosByName: [:])

    private struct MacroExpansionParameter: Sendable {
        var localName: String
        var externalLabel: String?
        var typeReference: TypeReference?
        var isBinding: Bool
        var capturesSyntax: Bool
    }

    private struct MacroExpansionSignature: Sendable {
        var genericParameterNames: Set<String>
        var parameters: [MacroExpansionParameter]
        var returnType: TypeReference
    }

    private let signaturesByName: [String: [MacroExpansionSignature]]

    public init(macrosByName: [String: MacroDeclaration]) {
        self.signaturesByName = macrosByName.mapValues { macro in
            guard let expansionType = macro.expansionType else {
                return []
            }
            return [
                MacroExpansionSignature(
                    genericParameterNames: Set(macro.genericParameters),
                    parameters: macro.parameters.map {
                        MacroExpansionParameter(
                            localName: $0.localName,
                            externalLabel: $0.externalLabel,
                            typeReference: $0.typeReference,
                            isBinding: $0.isBinding,
                            capturesSyntax: $0.capturesSyntax
                        )
                    },
                    returnType: expansionType
                )
            ]
        }
    }

    public func expansionReturnType(
        name: String,
        arguments: [DeclarationMacroExpansionArgument],
        literalBridgeResolver: LiteralBridgeResolver
    ) -> TypeReference? {
        let matches: [TypeReference] = signaturesByName[name, default: []].compactMap { signature in
            guard signature.parameters.count == arguments.count else {
                return nil
            }

            var bindings: [String: TypeReference] = [:]
            for (parameter, argument) in zip(signature.parameters, arguments) {
                guard argumentLabel(argument.label, matches: parameter) else {
                    return nil
                }
                if parameter.capturesSyntax {
                    continue
                }
                guard let expectedType = parameter.typeReference else {
                    continue
                }
                guard let actual = argument.type,
                    let actualType = materializedTypeReference(
                        for: actual,
                        resolver: literalBridgeResolver
                    )
                else {
                    return nil
                }
                guard
                    typeMatches(
                        actual: actualType,
                        expected: expectedType,
                        genericParameterNames: signature.genericParameterNames,
                        bindings: &bindings
                    )
                else {
                    return nil
                }
            }

            return Self.substitute(signature.returnType, using: bindings)
        }

        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private func argumentLabel(_ actualLabel: String?, matches parameter: MacroExpansionParameter)
        -> Bool
    {
        guard let actualLabel else {
            return true
        }
        let expectedLabel = parameter.externalLabel ?? parameter.localName
        return actualLabel == expectedLabel
    }

    private func materializedTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        case .nilLiteral:
            return .named("NilLiteral")
        default:
            return resolver.defaultDestinationType(for: type.displayName)
        }
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        genericParameterNames: Set<String>,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected, genericParameterNames.contains(name) {
            if let existing = bindings[name] {
                return existing == actual
            }
            bindings[name] = actual
            return true
        }

        if case .optional(let actualWrapped) = actual,
            case .generic(.named("Optional"), let expectedArguments) = expected,
            expectedArguments.count == 1
        {
            return typeMatches(
                actual: actualWrapped,
                expected: expectedArguments[0],
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        if case .generic(.named("Optional"), let actualArguments) = actual,
            actualArguments.count == 1,
            case .optional(let expectedWrapped) = expected
        {
            return typeMatches(
                actual: actualArguments[0],
                expected: expectedWrapped,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            else {
                return false
            }
            return zip(actualArguments, expectedArguments).allSatisfy {
                actualArgument, expectedArgument in
                typeMatches(
                    actual: actualArgument,
                    expected: expectedArgument,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }
            return zip(actualParameters, expectedParameters).allSatisfy {
                actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
                && typeMatches(
                    actual: actualReturn,
                    expected: expectedReturn,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        default:
            return false
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }
}

public struct DeclarationOperatorResolver: Sendable {
    public static let empty = DeclarationOperatorResolver(callablesByName: [:])

    private struct OperatorSignature: Sendable {
        var genericParameterNames: Set<String>
        var lhsType: TypeReference
        var rhsType: TypeReference
        var returnType: TypeReference
    }

    private let signaturesByName: [String: [OperatorSignature]]

    public init(callablesByName: [String: [CallableDeclaration]]) {
        self.signaturesByName = callablesByName.mapValues { callables in
            callables.compactMap { callable in
                guard callable.parameters.count == 2,
                    let lhsParameter = callable.parameters[0].typeReference,
                    let rhsParameter = callable.parameters[1].typeReference
                else {
                    return nil
                }

                return OperatorSignature(
                    genericParameterNames: Set(
                        callable.genericParameters.map(Self.genericParameterName)),
                    lhsType: lhsParameter,
                    rhsType: rhsParameter,
                    returnType: callable.returnType ?? .named("Void")
                )
            }
        }
    }

    public func binaryOperatorReturnType(
        symbol: String,
        lhs: BootstrapLiteralType,
        rhs: BootstrapLiteralType,
        literalBridgeResolver: LiteralBridgeResolver
    ) -> TypeReference? {
        guard let lhsType = materializedTypeReference(for: lhs, resolver: literalBridgeResolver),
            let rhsType = materializedTypeReference(for: rhs, resolver: literalBridgeResolver)
        else {
            return nil
        }

        let matches: [TypeReference] = signaturesByName[symbol, default: []].compactMap {
            signature in
            var bindings: [String: TypeReference] = [:]
            guard
                typeMatches(
                    actual: lhsType,
                    expected: signature.lhsType,
                    genericParameterNames: signature.genericParameterNames,
                    bindings: &bindings
                ),
                typeMatches(
                    actual: rhsType,
                    expected: signature.rhsType,
                    genericParameterNames: signature.genericParameterNames,
                    bindings: &bindings
                )
            else {
                return nil
            }
            return Self.substitute(signature.returnType, using: bindings)
        }

        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private func materializedTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        case .nilLiteral:
            return .named("NilLiteral")
        default:
            return resolver.defaultDestinationType(for: type.displayName)
        }
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        genericParameterNames: Set<String>,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected, genericParameterNames.contains(name) {
            if let existing = bindings[name] {
                return existing == actual
            }
            bindings[name] = actual
            return true
        }

        if case .optional(let actualWrapped) = actual,
            case .generic(.named("Optional"), let expectedArguments) = expected,
            expectedArguments.count == 1
        {
            return typeMatches(
                actual: actualWrapped,
                expected: expectedArguments[0],
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        if case .generic(.named("Optional"), let actualArguments) = actual,
            actualArguments.count == 1,
            case .optional(let expectedWrapped) = expected
        {
            return typeMatches(
                actual: actualArguments[0],
                expected: expectedWrapped,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            else {
                return false
            }
            return zip(actualArguments, expectedArguments).allSatisfy {
                actualArgument, expectedArgument in
                typeMatches(
                    actual: actualArgument,
                    expected: expectedArgument,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }
            return zip(actualParameters, expectedParameters).allSatisfy {
                actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
                && typeMatches(
                    actual: actualReturn,
                    expected: expectedReturn,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        default:
            return false
        }
    }

    private static func genericParameterName(_ parameter: GenericParameter) -> String {
        switch parameter {
        case .type(let name, _, _), .value(let name, _, _):
            return name
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }
}

public struct DeclarationMemberResolver: Sendable {
    public static let empty = DeclarationMemberResolver(constructsByName: [:])

    private struct ConstructMembers: Sendable {
        var genericParameterNames: [String]
        var genericDefaultArguments: [TypeReference?]
        var propertyTypes: [String: TypeReference]
        var callableReturnTypes: [String: TypeReference]
    }

    private let membersByConstructName: [String: ConstructMembers]

    public init(constructsByName: [String: ConstructDeclaration]) {
        self.membersByConstructName = constructsByName.mapValues { construct in
            let nestedTypeMap = Self.nestedTypeMap(for: construct)
            var propertyTypes: [String: TypeReference] = [:]
            for state in construct.states {
                propertyTypes[state.name] = Self.qualifyNestedLocalTypes(
                    state.type,
                    using: nestedTypeMap
                )
            }
            for environment in construct.environments {
                propertyTypes[environment.name] = Self.qualifyNestedLocalTypes(
                    environment.type,
                    using: nestedTypeMap
                )
            }
            for binding in construct.bindings {
                propertyTypes[binding.name] = Self.qualifyNestedLocalTypes(
                    Self.simpleTypeReference(named: binding.typeName),
                    using: nestedTypeMap
                )
            }
            for derived in construct.deriveds {
                propertyTypes[derived.name] = Self.qualifyNestedLocalTypes(
                    Self.simpleTypeReference(named: derived.typeName),
                    using: nestedTypeMap
                )
            }
            for value in construct.values {
                propertyTypes[value.name] = Self.qualifyNestedLocalTypes(
                    Self.simpleTypeReference(named: value.typeName),
                    using: nestedTypeMap
                )
            }

            var callableReturnTypes: [String: TypeReference] = [:]
            for callable in construct.callables {
                callableReturnTypes[callable.name] = Self.qualifyNestedLocalTypes(
                    callable.returnType ?? .named("Void"),
                    using: nestedTypeMap
                )
            }

            return ConstructMembers(
                genericParameterNames: construct.genericParameters.map(Self.genericParameterName),
                genericDefaultArguments: construct.genericParameters.map {
                    switch $0 {
                    case .type(_, _, let defaultArgument):
                        return defaultArgument
                    case .value:
                        return nil
                    }
                },
                propertyTypes: propertyTypes,
                callableReturnTypes: callableReturnTypes
            )
        }
    }

    private static func nestedTypeMap(for construct: ConstructDeclaration) -> [String:
        TypeReference]
    {
        Dictionary(
            uniqueKeysWithValues: construct.constructs.map { nested in
                let localName =
                    nested.name.split(separator: ".").last.map(String.init) ?? nested.name
                return (localName, .member(base: .named(construct.name), name: localName))
            }
        )
    }

    private static func qualifyNestedLocalTypes(
        _ type: TypeReference,
        using nestedTypeMap: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return nestedTypeMap[name] ?? type
        case .member(let base, let name):
            return .member(base: qualifyNestedLocalTypes(base, using: nestedTypeMap), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: qualifyNestedLocalTypes(base, using: nestedTypeMap),
                arguments: arguments.map { qualifyNestedLocalTypes($0, using: nestedTypeMap) }
            )
        case .array(let element):
            return .array(qualifyNestedLocalTypes(element, using: nestedTypeMap))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { qualifyNestedLocalTypes($0, using: nestedTypeMap) },
                returnType: qualifyNestedLocalTypes(returnType, using: nestedTypeMap)
            )
        case .optional(let wrapped):
            return .optional(qualifyNestedLocalTypes(wrapped, using: nestedTypeMap))
        case .variadic(let element):
            return .variadic(qualifyNestedLocalTypes(element, using: nestedTypeMap))
        }
    }

    public func memberType(baseType: TypeReference, memberName: String) -> TypeReference? {
        guard let context = constructContext(for: baseType),
            let members = membersByConstructName[context.name],
            let type = members.propertyTypes[memberName]
        else {
            return nil
        }
        return Self.substitute(
            type, using: genericSubstitution(for: members, arguments: context.arguments))
    }

    public func memberCallableReturnType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        guard let context = constructContext(for: baseType),
            let members = membersByConstructName[context.name],
            let type = members.callableReturnTypes[memberName]
        else {
            return nil
        }
        return Self.substitute(
            type, using: genericSubstitution(for: members, arguments: context.arguments))
    }

    public func constructType(forConstructorCallName name: String) -> TypeReference? {
        resolveConstructType(forConstructorCallName: name)
    }

    private func resolveConstructType(forConstructorCallName name: String) -> TypeReference? {
        guard let constructType = Self.parseConstructTypeReference(from: name),
            let context = constructContext(for: constructType),
            let members = membersByConstructName[context.name]
        else {
            return nil
        }

        guard
            members.genericParameterNames.isEmpty
                || resolvedGenericArguments(
                    for: members,
                    providedArguments: context.arguments
                ) != nil
        else {
            return nil
        }

        guard let resolvedArguments = resolvedGenericArguments(
            for: members,
            providedArguments: context.arguments
        ) else {
            return constructType
        }

        guard !resolvedArguments.isEmpty else {
            return constructType
        }

        return .generic(base: .named(context.name), arguments: resolvedArguments)
    }

    private func genericSubstitution(
        for members: ConstructMembers,
        arguments: [TypeReference]
    ) -> [String: TypeReference] {
        guard let resolvedArguments = resolvedGenericArguments(
            for: members,
            providedArguments: arguments
        ) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: zip(members.genericParameterNames, resolvedArguments))
    }

    private func resolvedGenericArguments(
        for members: ConstructMembers,
        providedArguments: [TypeReference]
    ) -> [TypeReference]? {
        guard providedArguments.count <= members.genericParameterNames.count else {
            return nil
        }

        var resolvedArguments = providedArguments
        if providedArguments.count == members.genericParameterNames.count {
            return resolvedArguments
        }

        for defaultArgument in members.genericDefaultArguments.dropFirst(providedArguments.count) {
            guard let defaultArgument else {
                return nil
            }
            resolvedArguments.append(defaultArgument)
        }

        return resolvedArguments
    }

    private func constructContext(for type: TypeReference) -> (
        name: String, arguments: [TypeReference]
    )? {
        switch type {
        case .named(let name):
            return (name, [])
        case .member:
            return (type.displayName, [])
        case .generic(let base, let arguments):
            guard let context = constructContext(for: base) else {
                return nil
            }
            return (context.name, arguments)
        case .array(let element):
            return ("Array", [element])
        case .optional(let wrapped):
            return ("Optional", [wrapped])
        case .function, .variadic:
            return nil
        }
    }

    private static func simpleTypeReference(named name: String) -> TypeReference {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") {
            trimmed.removeLast()
            return .optional(simpleTypeReference(named: trimmed))
        }
        return .named(trimmed)
    }

    private static func parseConstructTypeReference(from raw: String) -> TypeReference? {
        do {
            var parser = try Parser(source: raw)
            let type = try parser.parseTypeReferenceNode()
            try parser.consume(.eof)
            return type
        } catch {
            return nil
        }
    }

    private static func genericParameterName(_ parameter: GenericParameter) -> String {
        switch parameter {
        case .type(let name, _, _), .value(let name, _, _):
            return name
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }
}
