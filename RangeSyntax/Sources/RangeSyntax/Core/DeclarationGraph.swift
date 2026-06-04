import Foundation

public enum DeclarationSourceKind: Hashable {
    case type
    case macro
    case function
}

public struct DeclarationSourceLocation {
    public let name: String
    public let path: String
    public let range: RangeSourceRange
    public let kind: DeclarationSourceKind

    public init(
        name: String,
        path: String,
        range: RangeSourceRange,
        kind: DeclarationSourceKind
    ) {
        self.name = name
        self.path = path
        self.range = range
        self.kind = kind
    }
}

public struct DeclarationGraph {
    public let protocolsByName: [String: ProtocolDeclaration]
    public let packageValues: [ValueDeclaration]
    public let constructsByName: [String: ConstructDeclaration]
    public let enumsByName: [String: EnumDeclaration]
    public let macrosByName: [String: MacroDeclaration]
    public let macroMetadataByName: [String: MacroMetadataDeclaration]
    public let extensionsByTargetName: [String: [ExtensionDeclaration]]
    public let topLevelStatesByFilePath: [String: [StateDeclaration]]
    public let statesByConstructName: [String: [StateDeclaration]]
    public let bindingsByConstructName: [String: [BindingDeclaration]]
    public let derivedsByConstructName: [String: [DerivedDeclaration]]
    public let valuesByConstructName: [String: [ValueDeclaration]]
    public let initializersByConstructName: [String: [InitializerDeclaration]]
    public let parametersByCallableIdentity: [String: [RangeFunctionParameter]]
    public let parametersByInitializerIdentity: [String: [RangeFunctionParameter]]
    public let callablesByName: [String: [CallableDeclaration]]
    public let operatorCallablesByName: [String: [CallableDeclaration]]
    public let precedenceGroupsByName: [String: PrecedenceGroupDeclaration]
    public let sourceTextByPath: [String: String]
    public let sourceLocations: [DeclarationSourceLocation]
    public let realizedLiteralBridges: [RealizedLiteralBridge]
    public let realizedInitMacroTargets: [RealizedInitMacroTarget]
    public let programGraph: ProgramGraph

    public init(files: [ParsedSourceFile]) {
        let sourceTextByPath = Dictionary(
            uniqueKeysWithValues: files.compactMap { file in
                file.source.map { (file.path, $0) }
            }
        )
        let packageValues = Self.collectPackageManifestValues(from: files)
        let protocols = Self.collectProtocols(from: files)
        let macroMetadata = Self.collectMacroMetadata(from: files)
        let metadataSlotMacros = Self.metadataSlotMacroNames(in: macroMetadata)
        let extensions = Self.collectExtensions(from: files)
        let constructs = Self.collectConstructs(
            from: files,
            protocols: protocols,
            metadataSlotMacros: metadataSlotMacros
        )
        let enumerations = Self.collectEnums(from: files)
        let macros = Self.collectMacros(from: files)
        let topLevelStates = Self.collectTopLevelStates(from: files)
        let statesByConstructName = Self.collectStatesByConstructName(from: constructs)
        let bindingsByConstructName = Self.collectBindingsByConstructName(from: constructs)
        let derivedsByConstructName = Self.collectDerivedsByConstructName(from: constructs)
        let valuesByConstructName = Self.collectValuesByConstructName(from: constructs)
        let initializersByConstructName = Self.collectInitializersByConstructName(
            from: constructs,
            extensions: extensions
        )
        let callables = Self.collectCallables(from: files)
        let operatorCallables = Self.collectOperatorCallables(from: files)
        let precedenceGroups = Self.collectPrecedenceGroups(from: files)
        let parametersByCallableIdentity = Self.collectParametersByCallableIdentity(from: files)
        let parametersByInitializerIdentity = Self.collectParametersByInitializerIdentity(
            from: constructs,
            extensions: extensions
        )

        self.protocolsByName = protocols
        self.packageValues = packageValues
        self.constructsByName = constructs
        self.enumsByName = enumerations
        self.macrosByName = macros
        self.macroMetadataByName = macroMetadata
        self.extensionsByTargetName = extensions
        self.topLevelStatesByFilePath = topLevelStates
        self.statesByConstructName = statesByConstructName
        self.bindingsByConstructName = bindingsByConstructName
        self.derivedsByConstructName = derivedsByConstructName
        self.valuesByConstructName = valuesByConstructName
        self.initializersByConstructName = initializersByConstructName
        self.parametersByCallableIdentity = parametersByCallableIdentity
        self.parametersByInitializerIdentity = parametersByInitializerIdentity
        self.callablesByName = callables
        self.operatorCallablesByName = operatorCallables
        self.precedenceGroupsByName = precedenceGroups
        self.sourceTextByPath = sourceTextByPath
        self.sourceLocations = Self.collectSourceLocations(from: files)
        self.realizedLiteralBridges = Self.collectRealizedLiteralBridges(from: constructs)
        self.realizedInitMacroTargets = Self.collectRealizedInitMacroTargets(
            from: constructs,
            macrosByName: macros
        )
        self.programGraph = Self.collectProgramGraph(from: files)
    }

    public var views: DeclarationGraphViews {
        DeclarationGraphViews(
            literalBridgeResolver: LiteralBridgeResolver(realizedLiteralBridges: realizedLiteralBridges),
            memberResolver: DeclarationMemberResolver(
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                protocolsByName: protocolsByName,
                extensionsByTargetName: extensionsByTargetName
            ),
            operatorResolver: DeclarationOperatorResolver(callablesByName: operatorCallablesByName),
            typeCompatibilityResolver: DeclarationTypeCompatibilityResolver(
                protocolsByName: protocolsByName,
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                extensionsByTargetName: extensionsByTargetName
            ),
            registryView: DeclarationRegistryView(
                protocolsByName: protocolsByName,
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                macrosByName: macrosByName,
                extensionsByTargetName: extensionsByTargetName,
                topLevelStatesByFilePath: topLevelStatesByFilePath,
                statesByConstructName: statesByConstructName,
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
                constructsByName: constructsByName,
                extensionsByTargetName: extensionsByTargetName
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

    public var typeCompatibilityResolver: DeclarationTypeCompatibilityResolver {
        views.typeCompatibilityResolver
    }

    public var syntaxResolver: DeclarationSyntaxResolver {
        views.syntaxResolver
    }

    public var registryView: DeclarationRegistryView {
        views.registryView
    }

    public func topLevelStates(inFilePath path: String) -> [StateDeclaration] {
        registryView.topLevelStates(inFilePath: path)
    }

    public func states(onConstruct named: String) -> [StateDeclaration] {
        statesByConstructName[named, default: []]
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

    public func packageValues(named name: String) -> [ValueDeclaration] {
        packageValues.filter { $0.name == name }
    }

    public func initializers(onConstruct named: String) -> [InitializerDeclaration] {
        initializersByConstructName[named, default: []]
    }

    public func callables(onConstruct named: String) -> [CallableDeclaration] {
        let baseCallables = constructsByName[named]?.callables ?? []
        let extensionCallables = extensionsByTargetName[named, default: []].flatMap(\.callables)
        return baseCallables + extensionCallables
    }

    public func conformances(onConstruct named: String) -> [TypeReference] {
        let baseConformances = constructsByName[named]?.conformances ?? []
        let extensionConformances = extensionsByTargetName[named, default: []].flatMap(\.conformances)
        return baseConformances + extensionConformances
    }

    public func enumCases(onEnum named: String) -> [EnumCaseDeclaration] {
        let baseCases = enumsByName[named]?.cases ?? []
        let extensionCases = extensionsByTargetName[named, default: []].flatMap(\.enumCases)
        return baseCases + extensionCases
    }

    public func construct(named name: String) -> ConstructDeclaration? {
        constructsByName[name]
    }

    public func sourceLocation(
        named name: String,
        kinds: Set<DeclarationSourceKind>
    ) -> DeclarationSourceLocation? {
        sourceLocations.first { $0.name == name && kinds.contains($0.kind) }
    }

    public func hasConstruct(named name: String) -> Bool {
        constructsByName[name] != nil
    }

    public func macroApplicationHasMetadataSlotEffect(_ application: MacroApplication) -> Bool {
        macroMetadataByName[application.name]?.hasMetadataSlotEffect == true
    }

    public func isCoreConstruct(named name: String) -> Bool {
        constructsByName[name]?.isCore == true
    }

    public func callable(
        named callableName: String,
        onConstruct named: String
    ) -> CallableDeclaration? {
        callables(onConstruct: named).first(where: { $0.name == callableName })
    }

    public func memberKinds(
        forConstruct named: String
    ) -> [String: ApplicationGraphNodeKind] {
        var result: [String: ApplicationGraphNodeKind] = [:]
        for state in states(onConstruct: named) { result[state.name] = .state }
        for binding in bindings(onConstruct: named) { result[binding.name] = .binding }
        for derived in deriveds(onConstruct: named) { result[derived.name] = .derived }
        for value in values(onConstruct: named) { result[value.name] = .value }
        return result
    }

    public func constructTypedMemberNames(
        forConstruct named: String
    ) -> [String: String] {
        var result: [String: String] = [:]
        for binding in bindings(onConstruct: named) where hasConstruct(named: binding.typeName) {
            result[binding.name] = binding.typeName
        }
        for value in values(onConstruct: named) where hasConstruct(named: value.typeName) {
            result[value.name] = value.typeName
        }
        return result
    }

    public func declaredMemberSurfaces(
        forConstruct named: String
    ) -> [DeclaredMemberSurface] {
        var result: [DeclaredMemberSurface] = []
        result.append(contentsOf: states(onConstruct: named).map {
            DeclaredMemberSurface(
                ownerConstructName: named,
                name: $0.name,
                kind: .state,
                declaredTypeName: $0.type.displayName
            )
        })
        result.append(contentsOf: bindings(onConstruct: named).map {
            DeclaredMemberSurface(
                ownerConstructName: named,
                name: $0.name,
                kind: .binding,
                declaredTypeName: $0.typeName
            )
        })
        result.append(contentsOf: deriveds(onConstruct: named).map {
            DeclaredMemberSurface(
                ownerConstructName: named,
                name: $0.name,
                kind: .derived,
                declaredTypeName: $0.typeName
            )
        })
        result.append(contentsOf: values(onConstruct: named).map {
            DeclaredMemberSurface(
                ownerConstructName: named,
                name: $0.name,
                kind: .value,
                declaredTypeName: $0.typeName
            )
        })
        return result
    }

    public func declaresMember(
        named memberName: String,
        onConstruct named: String
    ) -> Bool {
        !declaredMemberSurfaces(forConstruct: named).filter { $0.name == memberName }.isEmpty
    }

    public func declaredMemberPaths(
        forConstruct named: String
    ) -> Set<String> {
        guard constructsByName[named] != nil else {
            return []
        }

        var paths: Set<String> = []

        func collect(
            constructName: String,
            prefix: String,
            activeTypes: Set<String>
        ) {
            guard !activeTypes.contains(constructName) else {
                return
            }

            let nextActiveTypes = activeTypes.union([constructName])
            for surface in declaredMemberSurfaces(forConstruct: constructName) {
                let memberPath = "\(prefix).\(surface.name)"
                paths.insert(memberPath)

                guard
                    let declaredTypeName = surface.declaredTypeName,
                    hasConstruct(named: declaredTypeName),
                    surface.kind == .binding || surface.kind == .value
                else {
                    continue
                }

                collect(
                    constructName: declaredTypeName,
                    prefix: memberPath,
                    activeTypes: nextActiveTypes
                )
            }
        }

        collect(constructName: named, prefix: named, activeTypes: [])
        return paths
    }

    public func declaresMemberPath(
        _ memberPath: String,
        onConstruct named: String
    ) -> Bool {
        declaredMemberPaths(forConstruct: named).contains(memberPath)
    }

    public func callableSurfaces(
        onConstruct named: String
    ) -> [DeclaredCallableSurface] {
        return callables(onConstruct: named).map { callable in
            DeclaredCallableSurface(
                ownerConstructName: named,
                name: callable.name,
                labels: callable.parameters.map(\.externalLabel),
                parameterTypeNames: callable.parameters.map {
                    $0.typeReference?.displayName ?? $0.slotName
                },
                parameters: callable.parameters,
                returnTypeName: callable.returnType?.displayName
            )
        }
    }

    public func topLevelCallableSurfaces(
        named callableName: String? = nil
    ) -> [DeclaredCallableSurface] {
        let names: [String]
        if let callableName {
            names = [callableName]
        } else {
            names = Array(callablesByName.keys).sorted()
        }

        return names.flatMap { name in
            callablesByName[name, default: []].map { callable in
                DeclaredCallableSurface(
                    ownerConstructName: nil,
                    name: callable.name,
                    labels: callable.parameters.map(\.externalLabel),
                    parameterTypeNames: callable.parameters.map {
                        $0.typeReference?.displayName ?? $0.slotName
                    },
                    parameters: callable.parameters,
                    returnTypeName: callable.returnType?.displayName
                )
            }
        }
    }

    public func initializerSurfaces(
        onConstruct named: String
    ) -> [DeclaredInitializerSurface] {
        var surfaces: [DeclaredInitializerSurface] = []
        if Self.hasCoreRuntimeDefaultInitializer(named) {
            surfaces.append(
                DeclaredInitializerSurface(
                    ownerConstructName: named,
                    labels: [],
                    parameterTypeNames: [],
                    parameters: [],
                    returnTypeName: nil
                )
            )
        }
        if let construct = constructsByName[named] {
            let parameters = directConstructApplicationParameters(for: construct)
            if !parameters.isEmpty || construct.initializers.isEmpty {
                surfaces.append(
                    DeclaredInitializerSurface(
                        ownerConstructName: named,
                        labels: parameters.map(\.externalLabel),
                        parameterTypeNames: parameters.map {
                            $0.typeReference?.displayName ?? $0.slotName
                        },
                        parameters: parameters,
                        returnTypeName: nil
                    )
                )
            }
        }
        surfaces.append(contentsOf: initializers(onConstruct: named).map { initializer in
            DeclaredInitializerSurface(
                ownerConstructName: named,
                labels: initializer.parameters.map(\.externalLabel),
                parameterTypeNames: initializer.parameters.map {
                    $0.typeReference?.displayName ?? $0.slotName
                },
                parameters: initializer.parameters,
                returnTypeName: initializer.returnType?.displayName
            )
        })
        return surfaces
    }

    private static func hasCoreRuntimeDefaultInitializer(_ constructName: String) -> Bool {
        constructName == "Date" || constructName == "DateTime"
    }

    public func directConstructApplicationParameters(
        for construct: ConstructDeclaration
    ) -> [RangeFunctionParameter] {
        Self.directConstructApplicationParameters(
            for: construct,
            constructsByName: constructsByName,
            macrosByName: macrosByName,
            activeConstructs: []
        )
    }

    static func directConstructApplicationParameters(
        for construct: ConstructDeclaration
    ) -> [RangeFunctionParameter] {
        directConstructApplicationParameters(
            for: construct,
            constructsByName: [:],
            macrosByName: [:],
            activeConstructs: []
        )
    }

    private static func directConstructApplicationParameters(
        for construct: ConstructDeclaration,
        constructsByName: [String: ConstructDeclaration],
        macrosByName: [String: MacroDeclaration],
        activeConstructs: Set<String>
    ) -> [RangeFunctionParameter] {
        let activeConstructs = activeConstructs.union([construct.name])

        let forwardedValues = construct.values.flatMap { value -> [RangeFunctionParameter] in
            if propertyForwardsInitializer(macros: value.macros, macrosByName: macrosByName),
                let forwardedConstruct = forwardedConstruct(
                    named: value.typeName,
                    constructsByName: constructsByName,
                    activeConstructs: activeConstructs
                )
            {
                return directConstructApplicationParameters(
                    for: forwardedConstruct,
                    constructsByName: constructsByName,
                    macrosByName: macrosByName,
                    activeConstructs: activeConstructs
                )
            }
            return []
        }
        let forwardedStates = construct.states.flatMap { state -> [RangeFunctionParameter] in
            if propertyForwardsInitializer(macros: state.macros, macrosByName: macrosByName),
                let forwardedConstruct = forwardedConstruct(
                    named: state.type.displayName,
                    constructsByName: constructsByName,
                    activeConstructs: activeConstructs
                )
            {
                return directConstructApplicationParameters(
                    for: forwardedConstruct,
                    constructsByName: constructsByName,
                    macrosByName: macrosByName,
                    activeConstructs: activeConstructs
                )
            }
            return []
        }

        let values = construct.values.compactMap { value -> RangeFunctionParameter? in
            if propertyForwardsInitializer(macros: value.macros, macrosByName: macrosByName) {
                return nil
            }
            let defaultValue = value.value ?? (value.typeName.hasSuffix("?") ? .nilLiteral : nil)
            return RangeFunctionParameter(
                macros: [],
                localName: value.localName,
                externalLabel: value.externalLabel ?? value.localName,
                typeReference: .named(value.typeName),
                defaultValue: defaultValue,
                slotName: nil,
                isBinding: false,
                capturesSyntax: false
            )
        }
        let states = construct.states.compactMap { state -> RangeFunctionParameter? in
            if propertyForwardsInitializer(macros: state.macros, macrosByName: macrosByName) {
                return nil
            }
            let defaultValue: Expression?
            switch state.storage {
            case .stored(let expression):
                defaultValue = expression
            case .declared:
                defaultValue = nil
            }
            return RangeFunctionParameter(
                macros: [],
                localName: state.name,
                externalLabel: state.name,
                typeReference: state.type,
                defaultValue: defaultValue,
                slotName: nil,
                isBinding: false,
                capturesSyntax: false
            )
        }
        let bindings = construct.bindings.compactMap { binding -> RangeFunctionParameter? in
            guard !binding.typeName.contains("@") && !binding.typeName.contains("#") else {
                return nil
            }
            return RangeFunctionParameter(
                macros: [],
                localName: binding.name,
                externalLabel: binding.externalLabel ?? binding.name,
                typeReference: .named(binding.typeName),
                slotName: nil,
                isBinding: true,
                capturesSyntax: false
            )
        }
        return forwardedValues + forwardedStates + values + states + bindings
    }

    private static func propertyForwardsInitializer(
        macros applications: [MacroApplication],
        macrosByName: [String: MacroDeclaration]
    ) -> Bool {
        applications.contains { application in
            guard let macro = macrosByName[application.name],
                let targetBinding = macro.bindings?.target
            else {
                return false
            }

            return MacroExpander.macroOperationExpressions(in: macro.body).contains { expression in
                guard case .call(let name, let arguments) = expression else {
                    return false
                }
                return name == "\(targetBinding).initializer.forward" && arguments.isEmpty
            }
        }
    }

    private static func forwardedConstruct(
        named rawName: String,
        constructsByName: [String: ConstructDeclaration],
        activeConstructs: Set<String>
    ) -> ConstructDeclaration? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeConstructs.contains(name) else {
            return nil
        }
        return constructsByName[name]
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

    static func collectPackageManifestValues(from files: [ParsedSourceFile]) -> [ValueDeclaration] {
        files.flatMap { parsedFile in
            constructs(in: parsedFile.sourceFile, metadataSlotMacros: [])
                .filter { $0.macros.contains { $0.name == "package" } }
                .flatMap(\.values)
        }
    }

    static func collectConstructs(
        from files: [ParsedSourceFile],
        protocols: [String: ProtocolDeclaration],
        metadataSlotMacros: Set<String>
    ) -> [String: ConstructDeclaration] {
        var registry: [String: ConstructDeclaration] = [:]
        for parsedFile in files {
            for declaration in constructs(
                in: parsedFile.sourceFile,
                metadataSlotMacros: metadataSlotMacros
            ) {
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

    static func collectMacroMetadata(from files: [ParsedSourceFile]) -> [String: MacroMetadataDeclaration] {
        var registry: [String: MacroMetadataDeclaration] = [:]
        for parsedFile in files {
            for declaration in macros(in: parsedFile.sourceFile) {
                guard let metadata = MacroExpander.metadataDeclaration(from: declaration) else {
                    continue
                }
                registry[metadata.name] = metadata
            }
        }
        return registry
    }

    static func collectSourceLocations(from files: [ParsedSourceFile]) -> [DeclarationSourceLocation] {
        files.flatMap { parsedFile -> [DeclarationSourceLocation] in
            guard let source = parsedFile.source else {
                return []
            }
            return sourceLocations(in: source, path: parsedFile.path)
        }
    }

    private static func sourceLocations(
        in source: String,
        path: String
    ) -> [DeclarationSourceLocation] {
        let lines = source.components(separatedBy: .newlines)
        var result: [DeclarationSourceLocation] = []

        for (lineIndex, line) in lines.enumerated() {
            result.append(
                contentsOf: declarationSourceLocations(
                    in: line,
                    lineIndex: lineIndex,
                    path: path,
                    pattern: #"\b(?:construct|protocol|enum)\s+([A-Z][A-Za-z0-9_]*)"#,
                    kind: .type
                )
            )
            result.append(
                contentsOf: declarationSourceLocations(
                    in: line,
                    lineIndex: lineIndex,
                    path: path,
                    pattern: #"\bmacro\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                    kind: .macro
                )
            )
            result.append(
                contentsOf: declarationSourceLocations(
                    in: line,
                    lineIndex: lineIndex,
                    path: path,
                    pattern: #"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                    kind: .function
                )
            )
        }

        return result
    }

    private static func declarationSourceLocations(
        in line: String,
        lineIndex: Int,
        path: String,
        pattern: String,
        kind: DeclarationSourceKind
    ) -> [DeclarationSourceLocation] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsLine = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            .compactMap { match in
                guard match.numberOfRanges > 1 else {
                    return nil
                }
                let nameRange = match.range(at: 1)
                guard nameRange.location != NSNotFound else {
                    return nil
                }
                let name = nsLine.substring(with: nameRange)
                return DeclarationSourceLocation(
                    name: name,
                    path: path,
                    range: RangeSourceRange(
                        start: RangeSourceLocation(
                            path: path,
                            line: lineIndex,
                            character: nameRange.location
                        ),
                        end: RangeSourceLocation(
                            path: path,
                            line: lineIndex,
                            character: nameRange.location + nameRange.length
                        )
                    ),
                    kind: kind
                )
            }
    }

    static func collectExtensions(from files: [ParsedSourceFile]) -> [String: [ExtensionDeclaration]] {
        var registry: [String: [ExtensionDeclaration]] = [:]
        for parsedFile in files {
            for declaration in extensions(in: parsedFile.sourceFile) {
                registry[declaration.targetName, default: []].append(declaration)
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
        from constructs: [String: ConstructDeclaration],
        extensions: [String: [ExtensionDeclaration]]
    ) -> [String: [InitializerDeclaration]] {
        var registry: [String: [InitializerDeclaration]] = [:]
        for (name, declaration) in constructs where !declaration.initializers.isEmpty {
            registry[name, default: []].append(contentsOf: declaration.initializers)
        }
        for (name, declarations) in extensions {
            let extensionInitializers = declarations.flatMap(\.initializers)
            if !extensionInitializers.isEmpty {
                registry[name, default: []].append(contentsOf: extensionInitializers)
            }
        }
        return registry
    }

    static func collectParametersByCallableIdentity(
        from files: [ParsedSourceFile]
    ) -> [String: [RangeFunctionParameter]] {
        var registry: [String: [RangeFunctionParameter]] = [:]

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
        from constructs: [String: ConstructDeclaration],
        extensions: [String: [ExtensionDeclaration]]
    ) -> [String: [RangeFunctionParameter]] {
        var registry: [String: [RangeFunctionParameter]] = [:]
        for (constructName, declaration) in constructs {
            for initializer in declaration.initializers {
                registry[initializerIdentity(
                    constructName: constructName,
                    declaration: initializer
                )] = initializer.parameters
            }
        }
        for (constructName, declarations) in extensions {
            for initializer in declarations.flatMap(\.initializers) {
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

    static func collectOperatorCallables(from files: [ParsedSourceFile]) -> [String: [CallableDeclaration]]
    {
        var registry = collectCallables(from: files)
        let operatorSymbols = Set(files.flatMap { operators(in: $0.sourceFile).map(\.symbol) })
        let extensions = collectExtensions(from: files)
        for declarations in extensions.values {
            for declaration in declarations {
                for callable in declaration.callables where operatorSymbols.contains(callable.name) {
                    registry[callable.name, default: []].append(callable)
                }
            }
        }
        return registry
    }

    static func collectPrecedenceGroups(
        from files: [ParsedSourceFile]
    ) -> [String: PrecedenceGroupDeclaration] {
        Dictionary(
            uniqueKeysWithValues: files
                .flatMap { precedenceGroups(in: $0.sourceFile) }
                .map { ($0.name, $0) }
        )
    }

    static func collectRealizedLiteralBridges(
        from constructs: [String: ConstructDeclaration]
    ) -> [RealizedLiteralBridge] {
        constructs.values.flatMap { construct in
            construct.callables.compactMap { callable in
                guard callable.parameters.count == 1 else {
                    return nil
                }

                guard
                    let literalMacro = callable.macros.first(where: { $0.name == "literal" }),
                    literalMacro.genericArguments.count == 1
                else {
                    return nil
                }

                return RealizedLiteralBridge(
                    initTarget: RealizedInitTarget(
                        constructName: construct.name,
                        parameterLabels: callable.parameters.map(\.externalLabel),
                        isCore: construct.isCore
                    ),
                    carrierTypeName: literalMacro.genericArguments[0].displayName
                )
            }
        }
    }

    static func collectRealizedInitMacroTargets(
        from constructs: [String: ConstructDeclaration],
        macrosByName: [String: MacroDeclaration]
    ) -> [RealizedInitMacroTarget] {
        constructs.values.flatMap { construct in
            var targets = construct.initializers.compactMap { initializer -> RealizedInitMacroTarget? in
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

            let constructInitMacros = construct.macros.filter { application in
                guard let macro = macrosByName[application.name], let target = macro.target else {
                    return false
                }
                return macroTargetAllows(target, kind: .initializer)
            }

            if !constructInitMacros.isEmpty {
                let parameters = directConstructApplicationParameters(
                    for: construct,
                    constructsByName: constructs,
                    macrosByName: macrosByName,
                    activeConstructs: []
                )
                let rewriteLabels = parameters.map(\.externalLabel)
                let applicationLabels: [String?] = parameters.count == 1 ? [nil] : rewriteLabels
                targets.append(
                    RealizedInitMacroTarget(
                        initTarget: RealizedInitTarget(
                            constructName: construct.name,
                            parameterLabels: applicationLabels,
                            isCore: construct.isCore
                        ),
                        rewriteInitTarget: RealizedInitTarget(
                            constructName: construct.name,
                            parameterLabels: rewriteLabels,
                            isCore: construct.isCore
                        ),
                        macros: constructInitMacros
                    )
                )
            }

            return targets
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

    static func constructs(
        in sourceFile: SourceFileNode,
        metadataSlotMacros: Set<String>
    ) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    static func metadataSlotMacroNames(
        in macroMetadata: [String: MacroMetadataDeclaration]
    ) -> Set<String> {
        Set(macroMetadata.values.filter(\.hasMetadataSlotEffect).map(\.name))
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

    static func operators(in sourceFile: SourceFileNode) -> [OperatorDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.operators
        case .construct, .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    static func precedenceGroups(in sourceFile: SourceFileNode) -> [PrecedenceGroupDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.precedenceGroups
        case .construct, .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
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
        registry: inout [String: [RangeFunctionParameter]],
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

    static func renderParameterList(_ parameters: [RangeFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
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
                            && $0.rawBodyLanguage == carriedMacro.rawBodyLanguage
                            && $0.rawBody == carriedMacro.rawBody
                    }
                }

            return InitializerDeclaration(
                macros: mergedMacros,
                parameters: initializer.parameters,
                returnType: initializer.returnType,
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

    static func collectProgramGraph(from files: [ParsedSourceFile]) -> ProgramGraph {
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
    private var syntaxByID: [String: SyntaxProjectionAccumulator] = [:]

    mutating func build() -> ProgramGraph {
        ProgramGraph(
            entities: Array(entitiesByID.values),
            relations: Array(relations),
            syntax: syntaxByID.values.map(\.syntax)
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

private struct SyntaxProjectionAccumulator {
    let identity: SemanticGraphEntity
    let declarations: [SemanticGraphEntity]
    let applications: [SemanticGraphEntity]

    var syntax: ProgramGraphSyntax {
        ProgramGraphSyntax(
            identity: identity,
            declarations: declarations,
            applications: applications
        )
    }
}

    private mutating func addConstruct(_ declaration: ConstructDeclaration, parentID: String) {
        let constructID = "\(parentID)/construct:\(declaration.name)"
        let label = declaration.isCore ? "@language \(declaration.name)" : declaration.name
        let entity = SemanticGraphEntity(id: constructID, kind: .construct, label: label)
        addEntity(entity)
        addRelation(from: parentID, to: constructID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: constructID)
        addTypeReferences(declaration.conformances, from: constructID, kind: .conformsTo)
        collectSyntaxProjection(
            identity: entity,
            macros: declaration.macros,
            nestedConstructs: declaration.constructs,
            ownerID: constructID
        )

        for state in declaration.states {
            addState(state, parentID: constructID)
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
        let label = declaration.isCore ? "@language \(declaration.name)" : declaration.name
        let entity = SemanticGraphEntity(id: protocolID, kind: .protocolDefinition, label: label)
        addEntity(entity)
        addRelation(from: parentID, to: protocolID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: protocolID)
        addTypeReferences(declaration.conformances, from: protocolID, kind: .conformsTo)
        collectSyntaxProjection(
            identity: entity,
            macros: declaration.macros,
            nestedConstructs: [],
            ownerID: protocolID
        )
    }

    private mutating func addMacroDeclaration(_ declaration: MacroDeclaration, parentID: String) {
        let macroID = "\(parentID)/macro:\(declaration.name)"
        addEntity(id: macroID, kind: .macro, label: declaration.name)
        addRelation(from: parentID, to: macroID, kind: .contains)
        if let target = declaration.target {
            addTypeReferences(target.typeReferences, from: macroID, kind: .targetsMacro)
        }
        if let expansionType = declaration.expansionType {
            addTypeReference(expansionType, from: macroID, kind: .referencesType)
        }
    }

    private mutating func addExtension(_ declaration: ExtensionDeclaration, parentID: String) {
        let extensionID = "\(parentID)/extension:\(declaration.targetType.displayName)"
        addEntity(id: extensionID, kind: .typeExtension, label: declaration.targetType.displayName)
        addRelation(from: parentID, to: extensionID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: extensionID)
        addTypeReference(declaration.targetType, from: extensionID, kind: .extends)
        addTypeReferences(declaration.conformances, from: extensionID, kind: .conformsTo)
    }

    private mutating func addState(_ declaration: StateDeclaration, parentID: String) {
        let stateID = "\(parentID)/state:\(declaration.name)"
        addEntity(id: stateID, kind: .state, label: declaration.name)
        addRelation(from: parentID, to: stateID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: stateID)
        addStorageTypeReference(declaration.type, from: stateID)
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
        if let returnType = declaration.returnType {
            addTypeReference(returnType, from: initializerID, kind: .referencesType)
        }
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

    private mutating func addParameter(_ parameter: RangeFunctionParameter, parentID: String) {
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
            addEntity(id: macroID, kind: .macroApplication, label: "@\(macro.name)")
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
        addEntity(SemanticGraphEntity(id: id, kind: kind, label: label))
    }

    private mutating func addEntity(_ entity: SemanticGraphEntity) {
        entitiesByID[entity.id] = entity
    }

    private mutating func collectSyntaxProjection(
        identity: SemanticGraphEntity,
        macros: [MacroApplication],
        nestedConstructs: [ConstructDeclaration],
        ownerID: String
    ) {
        guard hasMacro("syntax", in: macros) else { return }

        var declarations: [SemanticGraphEntity] = []
        var applications: [SemanticGraphEntity] = []

        if hasGraphRole(.declaration, in: macros) {
            declarations.append(identity)
        }
        if hasGraphRole(.application, in: macros) {
            applications.append(identity)
        }

        for nested in nestedConstructs {
            let nestedID = "\(ownerID)/construct:\(nested.name)"
            let nestedLabel = nested.isCore ? "@language \(nested.name)" : nested.name
            let nestedEntity = SemanticGraphEntity(
                id: nestedID,
                kind: .construct,
                label: nestedLabel
            )

            if hasGraphRole(.declaration, in: nested.macros) {
                declarations.append(nestedEntity)
            }
            if hasGraphRole(.application, in: nested.macros) {
                applications.append(nestedEntity)
            }
        }

        guard !declarations.isEmpty || !applications.isEmpty else { return }

        syntaxByID[identity.id] = SyntaxProjectionAccumulator(
            identity: identity,
            declarations: declarations,
            applications: applications
        )
    }

    private func hasMacro(_ name: String, in macros: [MacroApplication]) -> Bool {
        macros.contains { $0.name == name }
    }

    private enum GraphRoleMarker {
        case declaration
        case application
    }

    private func hasGraphRole(_ role: GraphRoleMarker, in macros: [MacroApplication]) -> Bool {
        let expected = role == .declaration ? ".declaration" : ".application"
        return macros.contains { macro in
            guard macro.name == "graph" else { return false }
            let clause = macro.argumentClause?.replacingOccurrences(of: " ", with: "")
            return clause == expected
        }
    }

    private mutating func addRelation(
        from sourceID: String,
        to targetID: String,
        kind: SemanticGraphRelationKind
    ) {
        relations.insert(SemanticGraphRelation(sourceID: sourceID, targetID: targetID, kind: kind))
    }

    private func renderParameterList(_ parameters: [RangeFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
                ?? "_"
            let label = parameter.externalLabel ?? "_"
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }

}
