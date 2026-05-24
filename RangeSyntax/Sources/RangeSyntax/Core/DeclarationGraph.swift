import Foundation

public enum DeclarationSourceKind: Hashable {
    case type
    case namespace
    case macro
    case marker
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
    public let packageSpaces: [PackageSpaceDeclaration]
    public let packageValues: [ValueDeclaration]
    public let namespacesByName: [String: NamespaceDeclaration]
    public let namespaceAttributeNames: Set<String>
    public let namespaceAttributeAttachments: [NamespaceAttributeAttachment]
    public let constructsByName: [String: ConstructDeclaration]
    public let enumsByName: [String: EnumDeclaration]
    public let macrosByName: [String: MacroDeclaration]
    public let markersByName: [String: MarkerDeclaration]
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
        let packageSpaces = Self.collectPackageSpaces(from: files)
        let packageValues = packageSpaces.flatMap(\.values)
            + Self.collectPackageManifestValues(from: files)
        let protocols = Self.collectProtocols(from: files)
        let markers = Self.collectMarkers(from: files)
        let metadataSlotMarkers = Self.metadataSlotMarkerNames(in: markers)
        let namespaces = Self.collectNamespaces(
            from: files,
            metadataSlotMarkers: metadataSlotMarkers
        )
        let namespaceAttributeNames = Self.collectNamespaceAttributeNames(
            from: files,
            metadataSlotMarkers: metadataSlotMarkers
        )
        let namespaceAttributeAttachments = Self.collectNamespaceAttributeAttachments(
            from: files,
            namespacesByName: namespaces
        )
        let extensions = Self.collectExtensions(from: files)
        let constructs = Self.collectConstructs(
            from: files,
            protocols: protocols,
            metadataSlotMarkers: metadataSlotMarkers
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
        let parametersByCallableIdentity = Self.collectParametersByCallableIdentity(from: files)
        let parametersByInitializerIdentity = Self.collectParametersByInitializerIdentity(
            from: constructs,
            extensions: extensions
        )

        self.protocolsByName = protocols
        self.packageSpaces = packageSpaces
        self.packageValues = packageValues
        self.namespacesByName = namespaces
        self.namespaceAttributeNames = namespaceAttributeNames
        self.namespaceAttributeAttachments = namespaceAttributeAttachments
        self.constructsByName = constructs
        self.enumsByName = enumerations
        self.macrosByName = macros
        self.markersByName = markers
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
        self.sourceTextByPath = sourceTextByPath
        self.sourceLocations = Self.collectSourceLocations(from: files)
        self.realizedLiteralBridges = Self.collectRealizedLiteralBridges(from: constructs)
        self.realizedInitMacroTargets = Self.collectRealizedInitMacroTargets(from: constructs)
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

    public func construct(named name: String) -> ConstructDeclaration? {
        constructsByName[name]
    }

    public func namespace(named name: String) -> NamespaceDeclaration? {
        namespacesByName[name]
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

    public func hasNamespace(named name: String) -> Bool {
        namespacesByName[name] != nil
    }

    public func hasNamespaceAttribute(named name: String) -> Bool {
        namespaceAttributeNames.contains(name)
    }

    public func markerApplicationHasMetadataSlotEffect(_ application: MacroApplication) -> Bool {
        markersByName[application.name]?.hasMetadataSlotEffect == true
    }

    public func isNamespaceShaped(_ declaration: ConstructDeclaration) -> Bool {
        false
    }

    public func namespaceDeclaration(from construct: ConstructDeclaration) -> NamespaceDeclaration {
        Self.namespaceDeclaration(
            from: construct,
            metadataSlotMarkers: Self.metadataSlotMarkerNames(in: markersByName)
        )
    }

    public func namespaceAttributeAttachments(
        onDeclarationNamed name: String
    ) -> [NamespaceAttributeAttachment] {
        namespaceAttributeAttachments.filter { $0.declarationName == name }
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
        if let construct = constructsByName[named] {
            let parameters = Self.directConstructApplicationParameters(for: construct)
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

    static func directConstructApplicationParameters(
        for construct: ConstructDeclaration
    ) -> [RangeFunctionParameter] {
        let values = construct.values.map { value in
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
        let states = construct.states.map { state in
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
        let bindings = construct.bindings.map { binding in
            RangeFunctionParameter(
                macros: [],
                localName: binding.name,
                externalLabel: binding.externalLabel ?? binding.name,
                typeReference: .named(binding.typeName),
                slotName: nil,
                isBinding: true,
                capturesSyntax: false
            )
        }
        return values + states + bindings
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

    static func collectPackageSpaces(from files: [ParsedSourceFile]) -> [PackageSpaceDeclaration] {
        files.flatMap { packageSpaces(in: $0.sourceFile) }
    }

    static func collectPackageManifestValues(from files: [ParsedSourceFile]) -> [ValueDeclaration] {
        files.flatMap { parsedFile in
            constructs(in: parsedFile.sourceFile, metadataSlotMarkers: [])
                .filter { $0.macros.contains { $0.name == "package" } }
                .flatMap(\.values)
        }
    }

    static func collectConstructs(
        from files: [ParsedSourceFile],
        protocols: [String: ProtocolDeclaration],
        metadataSlotMarkers: Set<String>
    ) -> [String: ConstructDeclaration] {
        var registry: [String: ConstructDeclaration] = [:]
        let namespaceRegistry = collectNamespaces(
            from: files,
            metadataSlotMarkers: metadataSlotMarkers
        )
        let extensions = collectExtensions(from: files)
        for parsedFile in files {
            for declaration in constructs(
                in: parsedFile.sourceFile,
                metadataSlotMarkers: metadataSlotMarkers
            ) {
                collectConstruct(
                    declaration,
                    qualifiedName: declaration.name,
                    into: &registry,
                    protocols: protocols
                )
            }
            for namespace in namespaces(
                in: parsedFile.sourceFile,
                metadataSlotMarkers: metadataSlotMarkers
            ) {
                collectNamespaceConstructs(
                    in: namespace,
                    qualifiedPrefix: namespace.name,
                    into: &registry,
                    protocols: protocols
                )
            }
        }
        for (targetName, declarations) in extensions where namespaceRegistry[targetName] != nil {
            for declaration in declarations {
                collectNamespaceExtensionConstructs(
                    from: declaration,
                    qualifiedPrefix: targetName,
                    into: &registry,
                    protocols: protocols
                )
            }
        }
        return registry
    }

    static func collectNamespaces(
        from files: [ParsedSourceFile],
        metadataSlotMarkers: Set<String>
    ) -> [String: NamespaceDeclaration] {
        var registry: [String: NamespaceDeclaration] = [:]
        for parsedFile in files {
            for declaration in namespaces(
                in: parsedFile.sourceFile,
                metadataSlotMarkers: metadataSlotMarkers
            ) {
                collectNamespace(
                    declaration,
                    qualifiedName: declaration.name,
                    into: &registry
                )
            }
        }
        return registry
    }

    static func collectNamespaceAttributeNames(
        from files: [ParsedSourceFile],
        metadataSlotMarkers: Set<String>
    ) -> Set<String> {
        var names: Set<String> = []
        for parsedFile in files {
            for declaration in namespaces(
                in: parsedFile.sourceFile,
                metadataSlotMarkers: metadataSlotMarkers
            ) {
                collectNamespaceAttributeName(declaration, into: &names)
            }
            for declaration in extensions(in: parsedFile.sourceFile) {
                collectNamespaceAttributeNames(in: declaration, into: &names)
            }
        }
        return names
    }

    static func collectNamespaceAttributeAttachments(
        from files: [ParsedSourceFile],
        namespacesByName: [String: NamespaceDeclaration]
    ) -> [NamespaceAttributeAttachment] {
        files.flatMap { parsedFile in
            namespaceAttributeAttachments(
                in: parsedFile.sourceFile,
                filePath: parsedFile.path,
                namespacesByName: namespacesByName
            )
        }
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

    static func collectMarkers(from files: [ParsedSourceFile]) -> [String: MarkerDeclaration] {
        var registry: [String: MarkerDeclaration] = [:]
        for parsedFile in files {
            for declaration in markers(in: parsedFile.sourceFile) {
                registry[declaration.name] = declaration
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
                    pattern: #"\bnamespace\s+([A-Z][A-Za-z0-9_]*)"#,
                    kind: .namespace
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
                    pattern: #"\bmarker\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                    kind: .marker
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
        let metadataSlotMarkers = metadataSlotMarkerNames(
            in: collectMarkers(from: files)
        )
        let namespaceRegistry = collectNamespaces(
            from: files,
            metadataSlotMarkers: metadataSlotMarkers
        )
        let extensions = collectExtensions(from: files)

        for parsedFile in files {
            switch parsedFile.sourceFile {
            case .module(let module):
                for callable in module.callables + module.packageSpaces.flatMap(\.callables) {
                    let identity = callableIdentity(
                        ownerName: nil,
                        declaration: callable
                    )
                    registry[identity] = callable.parameters
                }
                for construct in module.constructs + module.packageSpaces.flatMap(\.constructs)
                where !isNamespaceShaped(
                    construct,
                    metadataSlotMarkers: metadataSlotMarkers
                ) {
                    collectCallableParameters(
                        in: construct,
                        registry: &registry,
                        ownerName: construct.name
                    )
                }
                let namespaceConstructs = (module.constructs + module.packageSpaces.flatMap(\.constructs))
                    .filter {
                        isNamespaceShaped(
                            $0,
                            metadataSlotMarkers: metadataSlotMarkers
                        )
                    }
                    .map {
                        namespaceDeclaration(
                            from: $0,
                            metadataSlotMarkers: metadataSlotMarkers
                        )
                    }
                for namespace in module.namespaces + module.packageSpaces.flatMap(\.namespaces)
                    + namespaceConstructs
                {
                    collectNamespaceCallableParameters(
                        in: namespace,
                        registry: &registry,
                        qualifiedPrefix: namespace.name
                    )
                }
            case .construct(let construct):
                if isNamespaceShaped(
                    construct,
                    metadataSlotMarkers: metadataSlotMarkers
                ) {
                    let namespace = namespaceDeclaration(
                        from: construct,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                    collectNamespaceCallableParameters(
                        in: namespace,
                        registry: &registry,
                        qualifiedPrefix: namespace.name
                    )
                } else {
                    collectCallableParameters(
                        in: construct,
                        registry: &registry,
                        ownerName: construct.name
                    )
                }
            case .namespace(let namespace):
                collectNamespaceCallableParameters(
                    in: namespace,
                    registry: &registry,
                    qualifiedPrefix: namespace.name
                )
            case .enumeration, .protocolDefinition, .macro, .marker, .mainBlock, .extensions:
                continue
            }
        }
        for (targetName, declarations) in extensions where namespaceRegistry[targetName] != nil {
            for declaration in declarations {
                collectNamespaceExtensionCallableParameters(
                    from: declaration,
                    registry: &registry,
                    qualifiedPrefix: targetName
                )
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
        let metadataSlotMarkers = metadataSlotMarkerNames(
            in: collectMarkers(from: files)
        )
        let namespaceRegistry = collectNamespaces(
            from: files,
            metadataSlotMarkers: metadataSlotMarkers
        )
        let extensions = collectExtensions(from: files)
        for parsedFile in files {
            for declaration in callables(in: parsedFile.sourceFile) {
                registry[declaration.name, default: []].append(declaration)
            }
            for namespace in namespaces(
                in: parsedFile.sourceFile,
                metadataSlotMarkers: metadataSlotMarkers
            ) {
                collectNamespaceCallables(
                    in: namespace,
                    qualifiedPrefix: namespace.name,
                    into: &registry
                )
            }
        }
        for (targetName, declarations) in extensions where namespaceRegistry[targetName] != nil {
            for declaration in declarations {
                collectNamespaceExtensionCallables(
                    from: declaration,
                    qualifiedPrefix: targetName,
                    into: &registry
                )
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

    private static func collectNamespaceConstructs(
        in namespace: NamespaceDeclaration,
        qualifiedPrefix: String,
        into registry: inout [String: ConstructDeclaration],
        protocols: [String: ProtocolDeclaration]
    ) {
        for declaration in namespace.constructs {
            collectConstruct(
                declaration,
                qualifiedName: "\(qualifiedPrefix).\(declaration.name)",
                into: &registry,
                protocols: protocols
            )
        }
        for nested in namespace.namespaces {
            collectNamespaceConstructs(
                in: nested,
                qualifiedPrefix: "\(qualifiedPrefix).\(nested.name)",
                into: &registry,
                protocols: protocols
            )
        }
    }

    private static func collectNamespace(
        _ declaration: NamespaceDeclaration,
        qualifiedName: String,
        into registry: inout [String: NamespaceDeclaration]
    ) {
        let qualifiedChildren = declaration.namespaces.map { child in
            NamespaceDeclaration(
                name: "\(qualifiedName).\(child.name)",
                values: child.values,
                callables: child.callables,
                constructs: child.constructs,
                namespaces: child.namespaces
            )
        }

        registry[qualifiedName] = NamespaceDeclaration(
            name: qualifiedName,
            values: declaration.values,
            callables: declaration.callables,
            constructs: declaration.constructs,
            namespaces: qualifiedChildren
        )

        for child in declaration.namespaces {
            collectNamespace(
                child,
                qualifiedName: "\(qualifiedName).\(child.name)",
                into: &registry
            )
        }
    }

    private static func collectNamespaceAttributeName(
        _ declaration: NamespaceDeclaration,
        into names: inout Set<String>
    ) {
        names.insert(declaration.name)
        for child in declaration.namespaces {
            collectNamespaceAttributeName(child, into: &names)
        }
    }

    private static func collectNamespaceAttributeNames(
        in declaration: ExtensionDeclaration,
        into names: inout Set<String>
    ) {
        for namespace in declaration.namespaces {
            collectNamespaceAttributeName(namespace, into: &names)
        }
    }

    private static func namespaceAttributeAttachments(
        in sourceFile: SourceFileNode,
        filePath: String,
        namespacesByName: [String: NamespaceDeclaration]
    ) -> [NamespaceAttributeAttachment] {
        switch sourceFile {
        case .construct(let declaration):
            return namespaceAttributeAttachments(
                in: declaration,
                qualifiedName: declaration.name,
                filePath: filePath,
                namespacesByName: namespacesByName
            )
        case .module(let module):
            var attachments: [NamespaceAttributeAttachment] = []
            for declaration in module.constructs + module.packageSpaces.flatMap(\.constructs) {
                attachments.append(
                    contentsOf: namespaceAttributeAttachments(
                        in: declaration,
                        qualifiedName: declaration.name,
                        filePath: filePath,
                        namespacesByName: namespacesByName
                    )
                )
            }
            attachments.append(
                contentsOf: (module.protocols + module.packageSpaces.flatMap(\.protocols)).compactMap {
                    namespaceAttributeAttachment(
                        declarationName: $0.name,
                        declarationKind: .type,
                        attribute: $0.attribute,
                        filePath: filePath,
                        namespacesByName: namespacesByName
                    )
                }
            )
            attachments.append(
                contentsOf: (module.enumerations + module.packageSpaces.flatMap(\.enumerations)).compactMap {
                    namespaceAttributeAttachment(
                        declarationName: $0.name,
                        declarationKind: .type,
                        attribute: $0.attribute,
                        filePath: filePath,
                        namespacesByName: namespacesByName
                    )
                }
            )
            for namespace in module.namespaces + module.packageSpaces.flatMap(\.namespaces) {
                attachments.append(
                    contentsOf: namespaceAttributeAttachments(
                        in: namespace,
                        qualifiedPrefix: namespace.name,
                        filePath: filePath,
                        namespacesByName: namespacesByName
                    )
                )
            }
            for declaration in module.extensions {
                attachments.append(
                    contentsOf: namespaceAttributeAttachments(
                        in: declaration,
                        qualifiedPrefix: declaration.targetName,
                        filePath: filePath,
                        namespacesByName: namespacesByName
                    )
                )
            }
            return attachments
        case .namespace(let declaration):
            return namespaceAttributeAttachments(
                in: declaration,
                qualifiedPrefix: declaration.name,
                filePath: filePath,
                namespacesByName: namespacesByName
            )
        case .protocolDefinition(let declaration):
            return namespaceAttributeAttachment(
                declarationName: declaration.name,
                declarationKind: .type,
                attribute: declaration.attribute,
                filePath: filePath,
                namespacesByName: namespacesByName
            ).map { [$0] } ?? []
        case .enumeration(let declaration):
            return namespaceAttributeAttachment(
                declarationName: declaration.name,
                declarationKind: .type,
                attribute: declaration.attribute,
                filePath: filePath,
                namespacesByName: namespacesByName
            ).map { [$0] } ?? []
        case .extensions(let declarations):
            return declarations.flatMap {
                namespaceAttributeAttachments(
                    in: $0,
                    qualifiedPrefix: $0.targetName,
                    filePath: filePath,
                    namespacesByName: namespacesByName
                )
            }
        case .mainBlock, .macro, .marker:
            return []
        }
    }

    private static func namespaceAttributeAttachments(
        in declaration: ConstructDeclaration,
        qualifiedName: String,
        filePath: String,
        namespacesByName: [String: NamespaceDeclaration]
    ) -> [NamespaceAttributeAttachment] {
        var attachments: [NamespaceAttributeAttachment] = []
        if let attachment = namespaceAttributeAttachment(
            declarationName: qualifiedName,
            declarationKind: .type,
            attribute: declaration.attribute,
            filePath: filePath,
            namespacesByName: namespacesByName
        ) {
            attachments.append(attachment)
        }
        for child in declaration.constructs {
            attachments.append(
                contentsOf: namespaceAttributeAttachments(
                    in: child,
                    qualifiedName: "\(qualifiedName).\(child.name)",
                    filePath: filePath,
                    namespacesByName: namespacesByName
                )
            )
        }
        return attachments
    }

    private static func namespaceAttributeAttachments(
        in declaration: NamespaceDeclaration,
        qualifiedPrefix: String,
        filePath: String,
        namespacesByName: [String: NamespaceDeclaration]
    ) -> [NamespaceAttributeAttachment] {
        var attachments: [NamespaceAttributeAttachment] = []
        for construct in declaration.constructs {
            attachments.append(
                contentsOf: namespaceAttributeAttachments(
                    in: construct,
                    qualifiedName: "\(qualifiedPrefix).\(construct.name)",
                    filePath: filePath,
                    namespacesByName: namespacesByName
                )
            )
        }
        for namespace in declaration.namespaces {
            attachments.append(
                contentsOf: namespaceAttributeAttachments(
                    in: namespace,
                    qualifiedPrefix: "\(qualifiedPrefix).\(namespace.name)",
                    filePath: filePath,
                    namespacesByName: namespacesByName
                )
            )
        }
        return attachments
    }

    private static func namespaceAttributeAttachments(
        in declaration: ExtensionDeclaration,
        qualifiedPrefix: String,
        filePath: String,
        namespacesByName: [String: NamespaceDeclaration]
    ) -> [NamespaceAttributeAttachment] {
        var attachments: [NamespaceAttributeAttachment] = []
        for construct in declaration.constructs {
            attachments.append(
                contentsOf: namespaceAttributeAttachments(
                    in: construct,
                    qualifiedName: "\(qualifiedPrefix).\(construct.name)",
                    filePath: filePath,
                    namespacesByName: namespacesByName
                )
            )
        }
        for namespace in declaration.namespaces {
            attachments.append(
                contentsOf: namespaceAttributeAttachments(
                    in: namespace,
                    qualifiedPrefix: "\(qualifiedPrefix).\(namespace.name)",
                    filePath: filePath,
                    namespacesByName: namespacesByName
                )
            )
        }
        return attachments
    }

    private static func namespaceAttributeAttachment(
        declarationName: String,
        declarationKind: DeclarationSourceKind,
        attribute: AttributeApplication?,
        filePath: String,
        namespacesByName: [String: NamespaceDeclaration]
    ) -> NamespaceAttributeAttachment? {
        guard
            let attribute,
            !RangeSyntax.attributeIdentifiers.contains(attribute.name),
            let namespace = namespacesByName[attribute.name]
        else {
            return nil
        }

        return NamespaceAttributeAttachment(
            declarationName: declarationName,
            declarationKind: declarationKind,
            attribute: attribute,
            namespace: namespace,
            filePath: filePath
        )
    }

    private static func collectNamespaceExtensionConstructs(
        from declaration: ExtensionDeclaration,
        qualifiedPrefix: String,
        into registry: inout [String: ConstructDeclaration],
        protocols: [String: ProtocolDeclaration]
    ) {
        for construct in declaration.constructs {
            collectConstruct(
                construct,
                qualifiedName: "\(qualifiedPrefix).\(construct.name)",
                into: &registry,
                protocols: protocols
            )
        }
        for namespace in declaration.namespaces {
            collectNamespaceConstructs(
                in: namespace,
                qualifiedPrefix: "\(qualifiedPrefix).\(namespace.name)",
                into: &registry,
                protocols: protocols
            )
        }
    }

    private static func collectNamespaceCallables(
        in namespace: NamespaceDeclaration,
        qualifiedPrefix: String,
        into registry: inout [String: [CallableDeclaration]]
    ) {
        for callable in namespace.callables {
            let qualifiedName = "\(qualifiedPrefix).\(callable.name)"
            registry[qualifiedName, default: []].append(
                CallableDeclaration(
                    macros: callable.macros,
                    attribute: callable.attribute,
                    targetType: callable.targetType,
                    receiverType: callable.receiverType,
                    name: qualifiedName,
                    genericParameters: callable.genericParameters,
                    hasExplicitParameterClause: callable.hasExplicitParameterClause,
                    parameters: callable.parameters,
                    returnType: callable.returnType,
                    body: callable.body
                )
            )
        }
        for nested in namespace.namespaces {
            collectNamespaceCallables(
                in: nested,
                qualifiedPrefix: "\(qualifiedPrefix).\(nested.name)",
                into: &registry
            )
        }
    }

    private static func collectNamespaceExtensionCallables(
        from declaration: ExtensionDeclaration,
        qualifiedPrefix: String,
        into registry: inout [String: [CallableDeclaration]]
    ) {
        for callable in declaration.callables {
            let qualifiedName = "\(qualifiedPrefix).\(callable.name)"
            registry[qualifiedName, default: []].append(
                CallableDeclaration(
                    macros: callable.macros,
                    attribute: callable.attribute,
                    targetType: callable.targetType,
                    receiverType: callable.receiverType,
                    name: qualifiedName,
                    genericParameters: callable.genericParameters,
                    hasExplicitParameterClause: callable.hasExplicitParameterClause,
                    parameters: callable.parameters,
                    returnType: callable.returnType,
                    body: callable.body
                )
            )
        }
        for namespace in declaration.namespaces {
            collectNamespaceCallables(
                in: namespace,
                qualifiedPrefix: "\(qualifiedPrefix).\(namespace.name)",
                into: &registry
            )
        }
    }

    private static func collectNamespaceCallableParameters(
        in namespace: NamespaceDeclaration,
        registry: inout [String: [RangeFunctionParameter]],
        qualifiedPrefix: String
    ) {
        for callable in namespace.callables {
            let qualifiedName = "\(qualifiedPrefix).\(callable.name)"
            let qualifiedCallable = CallableDeclaration(
                macros: callable.macros,
                attribute: callable.attribute,
                targetType: callable.targetType,
                receiverType: callable.receiverType,
                name: qualifiedName,
                genericParameters: callable.genericParameters,
                hasExplicitParameterClause: callable.hasExplicitParameterClause,
                parameters: callable.parameters,
                returnType: callable.returnType,
                body: callable.body
            )
            registry[callableIdentity(ownerName: nil, declaration: qualifiedCallable)] =
                callable.parameters
        }
        for construct in namespace.constructs {
            collectCallableParameters(
                in: construct,
                registry: &registry,
                ownerName: "\(qualifiedPrefix).\(construct.name)"
            )
        }
        for nested in namespace.namespaces {
            collectNamespaceCallableParameters(
                in: nested,
                registry: &registry,
                qualifiedPrefix: "\(qualifiedPrefix).\(nested.name)"
            )
        }
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

    private static func collectNamespaceExtensionCallableParameters(
        from declaration: ExtensionDeclaration,
        registry: inout [String: [RangeFunctionParameter]],
        qualifiedPrefix: String
    ) {
        for callable in declaration.callables {
            let qualifiedName = "\(qualifiedPrefix).\(callable.name)"
            let qualifiedCallable = CallableDeclaration(
                macros: callable.macros,
                attribute: callable.attribute,
                targetType: callable.targetType,
                receiverType: callable.receiverType,
                name: qualifiedName,
                genericParameters: callable.genericParameters,
                hasExplicitParameterClause: callable.hasExplicitParameterClause,
                parameters: callable.parameters,
                returnType: callable.returnType,
                body: callable.body
            )
            registry[callableIdentity(ownerName: nil, declaration: qualifiedCallable)] =
                callable.parameters
        }
        for namespace in declaration.namespaces {
            collectNamespaceCallableParameters(
                in: namespace,
                registry: &registry,
                qualifiedPrefix: "\(qualifiedPrefix).\(namespace.name)"
            )
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
            return module.protocols + module.packageSpaces.flatMap(\.protocols)
        case .construct, .namespace, .enumeration, .mainBlock, .macro, .marker, .extensions:
            return []
        }
    }

    static func packageSpaces(in sourceFile: SourceFileNode) -> [PackageSpaceDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.packageSpaces
        case .construct, .namespace, .enumeration, .mainBlock, .macro, .marker, .protocolDefinition, .extensions:
            return []
        }
    }

    static func constructs(
        in sourceFile: SourceFileNode,
        metadataSlotMarkers: Set<String>
    ) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return isNamespaceShaped(
                declaration,
                metadataSlotMarkers: metadataSlotMarkers
            ) ? [] : [declaration]
        case .module(let module):
            return (module.constructs + module.packageSpaces.flatMap(\.constructs))
                .filter {
                    !isNamespaceShaped(
                        $0,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                }
        case .namespace, .enumeration, .mainBlock, .macro, .marker, .protocolDefinition, .extensions:
            return []
        }
    }

    static func namespaces(
        in sourceFile: SourceFileNode,
        metadataSlotMarkers: Set<String>
    ) -> [NamespaceDeclaration] {
        switch sourceFile {
        case .namespace(let declaration):
            return [declaration]
        case .module(let module):
            let namespaceConstructs = (module.constructs + module.packageSpaces.flatMap(\.constructs))
                .filter {
                    isNamespaceShaped(
                        $0,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                }
                .map {
                    namespaceDeclaration(
                        from: $0,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                }
            return module.namespaces + module.packageSpaces.flatMap(\.namespaces) + namespaceConstructs
        case .construct(let declaration):
            return isNamespaceShaped(
                declaration,
                metadataSlotMarkers: metadataSlotMarkers
            )
                ? [
                    namespaceDeclaration(
                        from: declaration,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                ] : []
        case .enumeration, .mainBlock, .macro, .marker, .protocolDefinition, .extensions:
            return []
        }
    }

    static func namespaceDeclaration(
        from construct: ConstructDeclaration,
        metadataSlotMarkers: Set<String>
    ) -> NamespaceDeclaration {
        NamespaceDeclaration(
            name: construct.name,
            values: construct.values,
            callables: construct.callables,
            constructs: construct.constructs.filter {
                !isNamespaceShaped($0, metadataSlotMarkers: metadataSlotMarkers)
            },
            namespaces: construct.constructs
                .filter {
                    isNamespaceShaped(
                        $0,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                }
                .map {
                    namespaceDeclaration(
                        from: $0,
                        metadataSlotMarkers: metadataSlotMarkers
                    )
                }
        )
    }

    static func metadataSlotMarkerNames(
        in markers: [String: MarkerDeclaration]
    ) -> Set<String> {
        Set(markers.values.filter(\.hasMetadataSlotEffect).map(\.name))
    }

    static func isNamespaceShaped(
        _ declaration: ConstructDeclaration,
        metadataSlotMarkers: Set<String>
    ) -> Bool {
        false
    }

    static func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .namespace, .enumeration, .protocolDefinition, .macro, .marker, .mainBlock, .extensions:
            return []
        }
    }

    static func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let declaration):
            return [declaration]
        case .module(let module):
            return module.enumerations + module.packageSpaces.flatMap(\.enumerations)
        case .construct, .namespace, .mainBlock, .macro, .marker, .protocolDefinition, .extensions:
            return []
        }
    }

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .namespace, .enumeration, .mainBlock, .protocolDefinition, .marker, .extensions:
            return []
        }
    }

    static func markers(in sourceFile: SourceFileNode) -> [MarkerDeclaration] {
        switch sourceFile {
        case .marker(let declaration):
            return [declaration]
        case .module(let module):
            return module.markers
        case .construct, .namespace, .enumeration, .mainBlock, .protocolDefinition, .macro, .extensions:
            return []
        }
    }

    static func extensions(in sourceFile: SourceFileNode) -> [ExtensionDeclaration] {
        switch sourceFile {
        case .extensions(let declarations):
            return declarations
        case .module(let module):
            return module.extensions
        case .construct, .namespace, .enumeration, .mainBlock, .macro, .marker, .protocolDefinition:
            return []
        }
    }

    static func operators(in sourceFile: SourceFileNode) -> [OperatorDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.operators
        case .construct, .namespace, .enumeration, .mainBlock, .macro, .marker, .protocolDefinition, .extensions:
            return []
        }
    }

    static func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables + module.packageSpaces.flatMap(\.callables)
        case .namespace(let declaration):
            return declaration.callables
        case .construct, .enumeration, .mainBlock, .macro, .marker, .protocolDefinition, .extensions:
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

    mutating func build() -> ProgramGraph {
        ProgramGraph(
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
        case .namespace(let declaration):
            addNamespace(declaration, parentID: fileID)
        case .enumeration(let declaration):
            addEnumeration(declaration, parentID: fileID)
        case .protocolDefinition(let declaration):
            addProtocol(declaration, parentID: fileID)
        case .macro(let declaration):
            addMacroDeclaration(declaration, parentID: fileID)
        case .marker(let declaration):
            addMarkerDeclaration(declaration, parentID: fileID)
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
            for (index, declaration) in module.packageSpaces.enumerated() {
                addPackageSpace(declaration, parentID: fileID, index: index)
            }
            for callable in module.callables {
                addCallable(callable, parentID: fileID)
            }
            for declaration in module.constructs {
                addConstruct(declaration, parentID: fileID)
            }
            for declaration in module.namespaces {
                addNamespace(declaration, parentID: fileID)
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
            for declaration in module.markers {
                addMarkerDeclaration(declaration, parentID: fileID)
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

    private mutating func addPackageSpace(
        _ declaration: PackageSpaceDeclaration,
        parentID: String,
        index: Int
    ) {
        let packageID = "\(parentID)/package:\(index)"
        addEntity(id: packageID, kind: .packageSpace, label: "#package")
        addRelation(from: parentID, to: packageID, kind: .contains)

        for value in declaration.values {
            addValue(value, parentID: packageID)
        }
        for (index, entry) in declaration.entries.enumerated() {
            addPackageEntry(entry, parentID: packageID, index: index)
        }
        for callable in declaration.callables {
            addCallable(callable, parentID: packageID)
        }
        for construct in declaration.constructs {
            addConstruct(construct, parentID: packageID)
        }
        for namespace in declaration.namespaces {
            addNamespace(namespace, parentID: packageID)
        }
        for declaration in declaration.enumerations {
            addEnumeration(declaration, parentID: packageID)
        }
        for declaration in declaration.protocols {
            addProtocol(declaration, parentID: packageID)
        }
    }

    private mutating func addPackageEntry(_ entry: Expression, parentID: String, index: Int) {
        let entryID = "\(parentID)/entry:\(index)"
        addEntity(id: entryID, kind: .packageEntry, label: packageEntryLabel(entry))
        addRelation(from: parentID, to: entryID, kind: .contains)
    }

    private func packageEntryLabel(_ entry: Expression) -> String {
        switch entry {
        case .call(let name, let arguments):
            if arguments.count == 1, arguments[0].label == nil,
                case .string(let value) = arguments[0].value
            {
                return "\(name)(\"\(value)\")"
            }
            return "\(name)(...)"
        case .identifier(let name):
            return name
        default:
            return "package entry"
        }
    }

    private mutating func addNamespace(_ declaration: NamespaceDeclaration, parentID: String) {
        let namespaceID = "\(parentID)/namespace:\(declaration.name)"
        addEntity(id: namespaceID, kind: .namespace, label: declaration.name)
        addRelation(from: parentID, to: namespaceID, kind: .contains)

        for value in declaration.values {
            addValue(value, parentID: namespaceID)
        }
        for callable in declaration.callables {
            addCallable(callable, parentID: namespaceID)
        }
        for construct in declaration.constructs {
            addConstruct(construct, parentID: namespaceID)
        }
        for namespace in declaration.namespaces {
            addNamespace(namespace, parentID: namespaceID)
        }
    }

    private mutating func addConstruct(_ declaration: ConstructDeclaration, parentID: String) {
        let constructID = "\(parentID)/construct:\(declaration.name)"
        let label = declaration.isCore ? "#language \(declaration.name)" : declaration.name
        addEntity(id: constructID, kind: .construct, label: label)
        addRelation(from: parentID, to: constructID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: constructID)
        addTypeReferences(declaration.conformances, from: constructID, kind: .conformsTo)

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
        let label = declaration.isCore ? "#language \(declaration.name)" : declaration.name
        addEntity(id: protocolID, kind: .protocolDefinition, label: label)
        addRelation(from: parentID, to: protocolID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: protocolID)
        addTypeReferences(declaration.conformances, from: protocolID, kind: .conformsTo)
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

    private mutating func addMarkerDeclaration(_ declaration: MarkerDeclaration, parentID: String) {
        let markerID = "\(parentID)/marker:\(declaration.name)"
        addEntity(id: markerID, kind: .marker, label: declaration.name)
        addRelation(from: parentID, to: markerID, kind: .contains)
        addTypeReferences(declaration.target.typeReferences, from: markerID, kind: .targetsMacro)
        addTypeReference(declaration.valueType, from: markerID, kind: .referencesType)
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
