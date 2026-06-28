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
    public let constructsByName: [String: ConstructDeclaration]
    public let enumsByName: [String: EnumDeclaration]
    public let macrosByName: [String: MacroDeclaration]
    public let macroMetadataByName: [String: MacroMetadataDeclaration]
    public let extensionsByTargetName: [String: [ExtensionDeclaration]]
    public let mainBlockMacros: [MacroApplication]
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

    public init(files: [ParsedSourceFile]) {
        let sourceTextByPath = Dictionary(
            uniqueKeysWithValues: files.compactMap { file in
                file.source.map { (file.path, $0) }
            }
        )
        let macroMetadata = Self.collectMacroMetadata(from: files)
        let metadataSlotMacros = Self.metadataSlotMacroNames(in: macroMetadata)
        let extensions = Self.collectExtensions(from: files)
        let mainBlockMacros = Self.collectMainBlockMacros(from: files)
        let constructs = Self.collectConstructs(
            from: files,
            metadataSlotMacros: metadataSlotMacros
        )
        let enumerations = Self.collectEnums(from: files)
        let macros = Self.collectMacros(from: files)
        let statesByConstructName = Self.collectStatesByConstructName(from: constructs)
        let bindingsByConstructName = Self.collectBindingsByConstructName(from: constructs)
        let derivedsByConstructName = Self.collectDerivedsByConstructName(from: constructs)
        let valuesByConstructName = Self.collectValuesByConstructName(from: constructs)
        let initializersByConstructName = Self.collectInitializersByConstructName(
            from: constructs,
            extensions: extensions
        )
        let callables = Self.collectCallables(from: constructs, extensions: extensions)
        let operatorCallables = Self.collectOperatorCallables(
            from: constructs,
            extensions: extensions
        )
        let parametersByCallableIdentity = Self.collectParametersByCallableIdentity(
            from: constructs,
            extensions: extensions
        )
        let parametersByInitializerIdentity = Self.collectParametersByInitializerIdentity(
            from: constructs,
            extensions: extensions
        )

        self.constructsByName = constructs
        self.enumsByName = enumerations
        self.macrosByName = macros
        self.macroMetadataByName = macroMetadata
        self.extensionsByTargetName = extensions
        self.mainBlockMacros = mainBlockMacros
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
    }

    public var views: DeclarationGraphViews {
        DeclarationGraphViews(
            literalBridgeResolver: LiteralBridgeResolver(realizedLiteralBridges: realizedLiteralBridges),
            memberResolver: DeclarationMemberResolver(
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                extensionsByTargetName: extensionsByTargetName
            ),
            operatorResolver: DeclarationOperatorResolver(callablesByName: operatorCallablesByName),
            typeCompatibilityResolver: DeclarationTypeCompatibilityResolver(
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                extensionsByTargetName: extensionsByTargetName
            ),
            registryView: DeclarationRegistryView(
                constructsByName: constructsByName,
                enumsByName: enumsByName,
                macrosByName: macrosByName,
                extensionsByTargetName: extensionsByTargetName,
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
                constructsByName: constructsByName,
                macrosByName: macrosByName,
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
    ) -> [String: DeclaredMemberKind] {
        var result: [String: DeclaredMemberKind] = [:]
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
                labels: callable.parameters.map { Optional($0.name) },
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
                    labels: callable.parameters.map { Optional($0.name) },
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
            let parameters = directConstructApplicationParameters(for: construct)
            if !parameters.isEmpty || construct.initializers.isEmpty {
                surfaces.append(
                    DeclaredInitializerSurface(
                        ownerConstructName: named,
                        labels: parameters.map { Optional($0.name) },
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
                labels: initializer.parameters.map { Optional($0.name) },
                parameterTypeNames: initializer.parameters.map {
                    $0.typeReference?.displayName ?? $0.slotName
                },
                parameters: initializer.parameters,
                returnTypeName: initializer.returnType?.displayName
            )
        })
        return surfaces
    }

    public func directConstructApplicationParameters(
        for construct: ConstructDeclaration
    ) -> [RangeFunctionParameter] {
        Self.directConstructApplicationParameters(for: construct)
    }

    static func directConstructApplicationParameters(
        for construct: ConstructDeclaration
    ) -> [RangeFunctionParameter] {
        let values = construct.values.map { value -> RangeFunctionParameter in
            let defaultValue =
                value.value ?? (value.typeName.hasPrefix("Optional<") ? .nilLiteral : nil)
            return RangeFunctionParameter(
                macros: [],
                name: value.name,
                typeReference: .named(value.typeName),
                defaultValue: defaultValue,
                slotName: nil,
                isBinding: false,
                capturesSyntax: false
            )
        }
        let states = construct.states.map { state -> RangeFunctionParameter in
            let defaultValue: Expression?
            switch state.storage {
            case .stored(let expression):
                defaultValue = expression
            case .declared:
                defaultValue = nil
            }
            return RangeFunctionParameter(
                macros: [],
                name: state.name,
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
                name: binding.name,
                typeReference: .named(binding.typeName),
                slotName: nil,
                isBinding: true,
                capturesSyntax: false
            )
        }
        return values + states + bindings
    }

    static func collectConstructs(
        from files: [ParsedSourceFile],
        metadataSlotMacros: Set<String>
    ) -> [String: ConstructDeclaration] {
        var registry: [String: ConstructDeclaration] = [:]
        for parsedFile in files {
            for declaration in emittedConstructs(in: parsedFile.sourceFile) {
                collectConstruct(
                    declaration,
                    qualifiedName: declaration.name,
                    into: &registry
                )
            }
        }
        return registry
    }

    private static func emittedConstructs(in sourceFile: ModuleFileNode) -> [ConstructDeclaration] {
        sourceFile.blockMacros.flatMap { blockMacro in
            blockMacro.macros.compactMap { application in
                guard let payload = application.evaluatedStringValue else {
                    return nil
                }
                return emittedConstruct(
                    from: payload,
                    application: application,
                    applications: blockMacro.macros
                )
            }
        }
    }

    private static func emittedConstruct(
        from payload: String,
        application: MacroApplication,
        applications: [MacroApplication]
    ) -> ConstructDeclaration? {
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else {
            return nil
        }
        let headerFields = emittedRecordFields(in: header)
        guard headerFields["kind"] == nil,
            header.split(separator: "|").first.map(String.init) == "construct",
            let name = headerFields["name"],
            !name.isEmpty
        else {
            return nil
        }

        let memberLines = Array(lines.dropFirst())
        let states = emittedStates(from: memberLines)
        let values = emittedValues(from: memberLines)
        let callables = emittedFunctions(from: memberLines)
        let macro = MacroApplication(
            name: application.name,
            genericArguments: application.genericArguments,
            argumentClause: application.argumentClause,
            rawBodyLanguage: application.rawBodyLanguage,
            rawBody: application.rawBody,
            evaluatedStringValue: payload
        )

        let constructMacros = applications.map { existing in
            existing.name == application.name ? macro : existing
        }

        return ConstructDeclaration(
            macros: constructMacros,
            kind: .declaration,
            attribute: nil,
            name: name,
            genericParameters: [],
            conformances: [],
            states: states,
            bindings: [],
            deriveds: [],
            values: values,
            initializers: [],
            callables: callables,
            constructs: []
        )
    }

    private static func emittedStates(from lines: [String]) -> [StateDeclaration] {
        var result: [StateDeclaration] = []
        var index = 0
        while index < lines.count {
            let fields = emittedRecordFields(in: lines[index])
            guard fields["kind"] == "state" else {
                index += 1
                continue
            }

            let stateLine = lines[index]
            let valueLine: String?
            if index + 1 < lines.count,
                emittedRecordFields(in: lines[index + 1])["kind"] == "value"
            {
                valueLine = lines[index + 1]
                index += 2
            } else {
                valueLine = nil
                index += 1
            }

            if let state = emittedState(from: stateLine, valueLine: valueLine) {
                result.append(state)
            }
        }
        return result
    }

    private static func emittedState(from line: String, valueLine: String?) -> StateDeclaration? {
        let fields = emittedRecordFields(in: line)
        guard fields["kind"] == "state",
            let name = fields["name"],
            !name.isEmpty
        else {
            return nil
        }
        let valueFields = valueLine.map(emittedRecordFields) ?? [:]
        let type = valueFields["type"] ?? fields["type"] ?? ""
        let current = valueFields["current"] ?? ""

        return StateDeclaration(
            macros: [],
            name: name,
            hasExplicitTypeAnnotation: true,
            type: emittedTypeReference(typeName: type),
            storage: current.isEmpty ? .declared : .stored(.identifier(current))
        )
    }

    private static func emittedValues(from lines: [String]) -> [ValueDeclaration] {
        var result: [ValueDeclaration] = []
        var index = 0
        while index < lines.count {
            let fields = emittedRecordFields(in: lines[index])
            guard fields["kind"] == "let" else {
                index += 1
                continue
            }

            let letLine = lines[index]
            let valueLine: String?
            if index + 1 < lines.count,
                emittedRecordFields(in: lines[index + 1])["kind"] == "value"
            {
                valueLine = lines[index + 1]
                index += 2
            } else {
                valueLine = nil
                index += 1
            }

            if let value = emittedValue(from: letLine, valueLine: valueLine) {
                result.append(value)
            }
        }
        return result
    }

    private static func emittedValue(from line: String, valueLine: String?) -> ValueDeclaration? {
        let fields = emittedRecordFields(in: line)
        guard fields["kind"] == "let",
            let name = fields["name"],
            !name.isEmpty
        else {
            return nil
        }
        let valueFields = valueLine.map(emittedRecordFields) ?? [:]
        let type = valueFields["type"] ?? fields["type"] ?? ""
        let current = valueFields["current"] ?? ""

        return ValueDeclaration(
            macros: [],
            name: name,
            typeName: emittedTypeReference(typeName: type).displayName,
            value: current.isEmpty ? nil : .identifier(current)
        )
    }

    private static func emittedFunctions(from lines: [String]) -> [CallableDeclaration] {
        var result: [CallableDeclaration] = []
        var index = 0
        while index < lines.count {
            let fields = emittedRecordFields(in: lines[index])
            guard fields["kind"] == "function" else {
                index += 1
                continue
            }

            var parameterLines: [String] = []
            var childIndex = index + 1
            while childIndex < lines.count {
                let childFields = emittedRecordFields(in: lines[childIndex])
                if childFields["kind"] == "parameter" {
                    parameterLines.append(lines[childIndex])
                    childIndex += 1
                    while childIndex < lines.count {
                        let parameterChildFields = emittedRecordFields(in: lines[childIndex])
                        guard parameterChildFields["kind"] == "value" else {
                            break
                        }
                        parameterLines.append(lines[childIndex])
                        childIndex += 1
                    }
                    continue
                }
                guard childFields["kind"] == "value" else {
                    break
                }
                childIndex += 1
            }

            if let function = emittedFunction(
                from: lines[index],
                parameters: emittedParameters(from: parameterLines)
            ) {
                result.append(function)
            }
            index = childIndex
        }
        return result
    }

    private static func emittedFunction(
        from line: String,
        parameters: [RangeFunctionParameter] = []
    ) -> CallableDeclaration? {
        let fields = emittedRecordFields(in: line)
        guard fields["kind"] == "function",
            let name = fields["name"],
            !name.isEmpty
        else {
            return nil
        }
        let body = fields["body"].map { [Statement.expression(.identifier($0))] }

        return CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            name: name,
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: parameters,
            returnType: emittedTypeReference(typeName: fields["result"]),
            body: body
        )
    }

    private static func emittedParameters(from lines: [String]) -> [RangeFunctionParameter] {
        var result: [RangeFunctionParameter] = []
        var index = 0
        while index < lines.count {
            let fields = emittedRecordFields(in: lines[index])
            guard fields["kind"] == "parameter" else {
                index += 1
                continue
            }
            let valueLine: String?
            if index + 1 < lines.count,
                emittedRecordFields(in: lines[index + 1])["kind"] == "value"
            {
                valueLine = lines[index + 1]
                index += 2
            } else {
                valueLine = nil
                index += 1
            }
            if let parameter = emittedParameter(from: lines[index - (valueLine == nil ? 1 : 2)], valueLine: valueLine) {
                result.append(parameter)
            }
        }
        return result
    }

    private static func emittedParameter(from line: String, valueLine: String?) -> RangeFunctionParameter? {
        let fields = emittedRecordFields(in: line)
        guard fields["kind"] == "parameter",
            let name = fields["name"],
            !name.isEmpty
        else {
            return nil
        }
        let valueFields = valueLine.map(emittedRecordFields) ?? [:]
        let type = valueFields["type"] ?? fields["type"] ?? ""
        let defaultValue = valueFields["current"].flatMap { current -> Expression? in
            current.isEmpty ? nil : .identifier(current)
        }

        return RangeFunctionParameter(
            macros: [],
            name: name,
            typeReference: emittedTypeReference(typeName: type),
            defaultValue: defaultValue,
            slotName: nil
        )
    }

    private static func emittedRecordFields(in line: String) -> [String: String] {
        var fields: [String: String] = [:]
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        for part in parts.dropFirst() {
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                continue
            }
            fields[String(pieces[0])] = String(pieces[1])
        }
        return fields
    }

    private static func emittedTypeReference(typeName: String?) -> TypeReference {
        guard let typeName, !typeName.isEmpty else {
            return .named("Unknown")
        }
        return .named(typeName)
    }

    static func collectEnums(from files: [ParsedSourceFile]) -> [String: EnumDeclaration] {
        var registry: [String: EnumDeclaration] = [:]
        for parsedFile in files {
            for declaration in emittedEnums(in: parsedFile.sourceFile) {
                registry[declaration.name] = declaration
            }
        }
        return registry
    }

    private static func emittedEnums(in sourceFile: ModuleFileNode) -> [EnumDeclaration] {
        sourceFile.blockMacros.flatMap { blockMacro in
            blockMacro.macros.compactMap { application in
                guard let payload = application.evaluatedStringValue else {
                    return nil
                }
                return emittedEnum(from: payload, application: application)
            }
        }
    }

    private static func emittedEnum(
        from payload: String,
        application: MacroApplication
    ) -> EnumDeclaration? {
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else {
            return nil
        }
        let headerFields = emittedRecordFields(in: header)
        guard headerFields["kind"] == nil,
            header.split(separator: "|").first.map(String.init) == "enum",
            let name = headerFields["name"],
            !name.isEmpty
        else {
            return nil
        }

        let macro = MacroApplication(
            name: application.name,
            genericArguments: application.genericArguments,
            argumentClause: application.argumentClause,
            rawBodyLanguage: application.rawBodyLanguage,
            rawBody: application.rawBody,
            evaluatedStringValue: payload
        )

        return EnumDeclaration(
            macros: [macro],
            extensibility: .closed,
            attribute: nil,
            name: name,
            genericParameters: [],
            conformances: [],
            cases: lines.dropFirst().compactMap(emittedEnumCase)
        )
    }

    private static func emittedEnumCase(from line: String) -> EnumCaseDeclaration? {
        let fields = emittedRecordFields(in: line)
        guard fields["kind"] == "case",
            let name = fields["name"],
            !name.isEmpty
        else {
            return nil
        }
        return EnumCaseDeclaration(name: name, associatedValues: [])
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

    static func collectMainBlockMacros(from files: [ParsedSourceFile]) -> [MacroApplication] {
        files.flatMap { parsedFile -> [MacroApplication] in
            parsedFile.sourceFile.blockMacros
                .filter { $0.macros.first?.name == "main" }
                .flatMap(\.macros)
        }
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
        from constructs: [String: ConstructDeclaration],
        extensions: [String: [ExtensionDeclaration]]
    ) -> [String: [RangeFunctionParameter]] {
        var registry: [String: [RangeFunctionParameter]] = [:]

        for (constructName, construct) in constructs {
            for callable in construct.callables {
                registry[
                    callableIdentity(ownerName: constructName, declaration: callable)
                ] = callable.parameters
            }
        }
        for (targetName, declarations) in extensions {
            for extensionDeclaration in declarations {
                for callable in extensionDeclaration.callables {
                    registry[
                        callableIdentity(ownerName: targetName, declaration: callable)
                    ] = callable.parameters
                }
                for construct in extensionDeclaration.constructs {
                    collectCallableParameters(
                        in: construct,
                        registry: &registry,
                        ownerName: "\(targetName).\(construct.name)"
                    )
                }
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
        into registry: inout [String: ConstructDeclaration]
    ) {
        let qualifiedChildren = declaration.constructs.map { child in
            qualifiedConstruct(child, qualifiedName: "\(qualifiedName).\(child.name)")
        }

        let collected = ConstructDeclaration(
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
            constructs: qualifiedChildren
        )
        if let existing = registry[qualifiedName] {
            registry[qualifiedName] = mergedConstruct(existing, collected)
        } else {
            registry[qualifiedName] = collected
        }

        for child in declaration.constructs {
            collectConstruct(
                child,
                qualifiedName: "\(qualifiedName).\(child.name)",
                into: &registry
            )
        }
    }

    private static func mergedConstruct(
        _ first: ConstructDeclaration,
        _ second: ConstructDeclaration
    ) -> ConstructDeclaration {
        ConstructDeclaration(
            macros: first.macros + second.macros,
            kind: first.kind,
            attribute: first.attribute ?? second.attribute,
            name: first.name,
            genericParameters: first.genericParameters + second.genericParameters,
            conformances: first.conformances + second.conformances,
            states: first.states + second.states,
            bindings: first.bindings + second.bindings,
            deriveds: first.deriveds + second.deriveds,
            values: first.values + second.values,
            initializers: first.initializers + second.initializers,
            callables: first.callables + second.callables,
            constructs: first.constructs + second.constructs
        )
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

    static func collectCallables(
        from constructs: [String: ConstructDeclaration],
        extensions: [String: [ExtensionDeclaration]]
    ) -> [String: [CallableDeclaration]] {
        var registry: [String: [CallableDeclaration]] = [:]
        var seen: Set<String> = []

        func append(_ declaration: CallableDeclaration, ownerName: String) {
            let identity = callableIdentity(ownerName: ownerName, declaration: declaration)
            guard seen.insert(identity).inserted else {
                return
            }
            registry[declaration.name, default: []].append(declaration)
        }

        for (constructName, construct) in constructs {
            for declaration in construct.callables {
                append(declaration, ownerName: constructName)
            }
        }
        for (targetName, declarations) in extensions {
            for extensionDeclaration in declarations {
                for declaration in extensionDeclaration.callables {
                    append(declaration, ownerName: targetName)
                }
                for construct in extensionDeclaration.constructs {
                    collectCallables(
                        in: construct,
                        ownerName: "\(targetName).\(construct.name)",
                        registry: &registry,
                        seen: &seen
                    )
                }
            }
        }
        return registry
    }

    static func collectOperatorCallables(
        from constructs: [String: ConstructDeclaration],
        extensions: [String: [ExtensionDeclaration]]
    ) -> [String: [CallableDeclaration]] {
        collectCallables(from: constructs, extensions: extensions)
    }

    static func collectRealizedLiteralBridges(
        from constructs: [String: ConstructDeclaration]
    ) -> [RealizedLiteralBridge] {
        let literalCarrierNames = Set(
            constructs.values
                .filter { $0.macros.contains(where: { $0.name == "literal" }) }
                .map(\.name)
        )

        return constructs.values.flatMap { construct -> [RealizedLiteralBridge] in
            construct.callables.compactMap { callable -> RealizedLiteralBridge? in
                guard callable.name == "literal",
                    callable.parameters.count == 1,
                    let carrierType = callable.parameters[0].typeReference,
                    literalCarrierNames.contains(carrierType.displayName)
                else {
                    return nil
                }

                return RealizedLiteralBridge(
                    initTarget: RealizedInitTarget(
                        constructName: construct.name,
                        parameterLabels: callable.parameters.map { Optional($0.name) },
                        isCore: construct.isCore
                    ),
                    carrierTypeName: carrierType.displayName
                )
            }
        }
    }

    static func constructs(
        in sourceFile: ModuleFileNode,
        metadataSlotMacros: Set<String>
    ) -> [ConstructDeclaration] {
        sourceFile.constructs
    }

    static func metadataSlotMacroNames(
        in macroMetadata: [String: MacroMetadataDeclaration]
    ) -> Set<String> {
        Set(macroMetadata.values.filter(\.hasMetadataSlotEffect).map(\.name))
    }

    static func enumerations(in sourceFile: ModuleFileNode) -> [EnumDeclaration] {
        sourceFile.enumerations
    }

    static func macros(in sourceFile: ModuleFileNode) -> [MacroDeclaration] {
        sourceFile.macros
    }

    static func extensions(in sourceFile: ModuleFileNode) -> [ExtensionDeclaration] {
        sourceFile.extensions
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

    private static func collectCallables(
        in construct: ConstructDeclaration,
        ownerName: String,
        registry: inout [String: [CallableDeclaration]],
        seen: inout Set<String>
    ) {
        for callable in construct.callables {
            let identity = callableIdentity(ownerName: ownerName, declaration: callable)
            guard seen.insert(identity).inserted else {
                continue
            }
            registry[callable.name, default: []].append(callable)
        }

        for child in construct.constructs {
            collectCallables(
                in: child,
                ownerName: "\(ownerName).\(child.name)",
                registry: &registry,
                seen: &seen
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
            let label = parameter.name
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }

}
