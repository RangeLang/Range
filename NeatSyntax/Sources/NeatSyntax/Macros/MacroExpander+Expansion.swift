extension MacroExpander {
    struct EmittedDeclarationBundle {
        var states: [StateDeclaration] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var protocols: [ProtocolDeclaration] = []
        var extensions: [ExtensionDeclaration] = []

        mutating func merge(_ other: EmittedDeclarationBundle) {
            states.append(contentsOf: other.states)
            callables.append(contentsOf: other.callables)
            constructs.append(contentsOf: other.constructs)
            namespaces.append(contentsOf: other.namespaces)
            enumerations.append(contentsOf: other.enumerations)
            protocols.append(contentsOf: other.protocols)
            extensions.append(contentsOf: other.extensions)
        }
    }

    static func expand(
        sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext
    ) throws -> SourceFileNode {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .mainBlock(
                MainBlockNode(
                    body: try expand(
                        statements: mainBlock.body,
                        expectedReturnType: nil,
                        macros: macros,
                        protocols: protocols,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context
                    ))
            )
        case .module(let module):
            let moduleStateEffects = try propertyMacroEffects(
                states: module.states,
                values: [],
                bindings: [],
                deriveds: [],
                macros: macros,
                context: context
            )
            let expandedConstructs = try module.constructs.map {
                try expand(
                    construct: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
                )
            }
            let emittedDeclarationBundles = try module.constructs.map {
                try emittedDeclarations(from: $0, macros: macros, context: context)
            }
            return .module(
                ModuleFileNode(
                    mainBlock: try module.mainBlock.map {
                        MainBlockNode(
                            body: try expand(
                                statements: $0.body,
                                expectedReturnType: nil,
                                macros: macros,
                                protocols: protocols,
                                parameterMacroSignatures: parameterMacroSignatures,
                                literalBridges: literalBridges,
                                context: context,
                                stateEffects: moduleStateEffects
                            ))
                    },
                    states: try module.states.map {
                        try expand(
                            state: $0,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context
                        )
                    } + emittedDeclarationBundles.flatMap(\.states),
                    callables: try module.callables.map {
                        try expand(
                            callable: $0,
                            macros: macros,
                            protocols: protocols,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: moduleStateEffects
                        )
                    } + emittedDeclarationBundles.flatMap(\.callables),
                    constructs: expandedConstructs + emittedDeclarationBundles.flatMap(\.constructs),
                    namespaces: module.namespaces + emittedDeclarationBundles.flatMap(\.namespaces),
                    enumerations: module.enumerations + emittedDeclarationBundles.flatMap(\.enumerations),
                    protocols: module.protocols + emittedDeclarationBundles.flatMap(\.protocols),
                    macros: module.macros,
                    precedenceGroups: module.precedenceGroups,
                    operators: module.operators,
                    extensions: module.extensions + emittedDeclarationBundles.flatMap(\.extensions)
                )
            )
        case .construct(let declaration):
            let expandedConstruct = try expand(
                construct: declaration,
                macros: macros,
                protocols: protocols,
                parameterMacroSignatures: parameterMacroSignatures,
                literalBridges: literalBridges,
                context: context
            )
            let emittedBundle = try emittedDeclarations(
                from: declaration,
                macros: macros,
                context: context
            )
            guard
                !emittedBundle.states.isEmpty
                    || !emittedBundle.callables.isEmpty
                    || !emittedBundle.constructs.isEmpty
                    || !emittedBundle.namespaces.isEmpty
                    || !emittedBundle.enumerations.isEmpty
                    || !emittedBundle.protocols.isEmpty
                    || !emittedBundle.extensions.isEmpty
            else {
                return .construct(expandedConstruct)
            }
            return .module(
                ModuleFileNode(
                    mainBlock: nil,
                    states: emittedBundle.states,
                    callables: emittedBundle.callables,
                    constructs: [expandedConstruct] + emittedBundle.constructs,
                    namespaces: emittedBundle.namespaces,
                    enumerations: emittedBundle.enumerations,
                    protocols: emittedBundle.protocols,
                    macros: [],
                    precedenceGroups: [],
                    operators: [],
                    extensions: emittedBundle.extensions
                )
            )
        case .namespace, .macro, .enumeration, .protocolDefinition, .extensions:
            return sourceFile
        }
    }

    static func expand(
        construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext
    ) throws -> ConstructDeclaration {
        try validateConstructMacros(
            applications: construct.macros,
            macros: macros,
            context: context
        )

        let constructStateEffects = try propertyMacroEffects(
            states: construct.states,
            values: construct.values,
            bindings: construct.bindings,
            deriveds: construct.deriveds,
            macros: macros,
            context: context
        )

        let carriedInitializers = DeclarationGraph.carriedProtocolInitializerMacros(
            for: construct.initializers,
            conformances: construct.conformances,
            protocols: protocols
        )

        return ConstructDeclaration(
            macros: construct.macros,
            kind: construct.kind,
            attribute: construct.attribute,
            name: construct.name,
            genericParameters: construct.genericParameters,
            conformances: construct.conformances,
            states: try construct.states.map {
                try expand(
                    state: $0,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: constructStateEffects
                )
            },
            environments: construct.environments,
            bindings: try construct.bindings.map {
                try expand(
                    binding: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: constructStateEffects
                )
            },
            deriveds: try construct.deriveds.map {
                try expand(
                    derived: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: constructStateEffects
                )
            },
            values: try construct.values.map {
                try expand(
                    value: $0,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: constructStateEffects
                )
            },
            initializers: try carriedInitializers.map {
                try expand(
                    initializer: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: constructStateEffects
                )
            },
            callables: try construct.callables.map {
                try expand(
                    callable: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: constructStateEffects
                )
            },
            constructs: try construct.constructs.map {
                try expand(
                    construct: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
                )
            }
        )
    }

    static func expand(
        callable: CallableDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> CallableDeclaration {
        CallableDeclaration(
            macros: callable.macros,
            attribute: callable.attribute,
            targetType: callable.targetType,
            name: callable.name,
            genericParameters: callable.genericParameters,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: try expand(parameters: callable.parameters, macros: macros, context: context),
            returnType: callable.returnType,
            body: try callable.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: callable.returnType,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            }
        )
    }

    static func expand(
        initializer: InitializerDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> InitializerDeclaration {
        InitializerDeclaration(
            macros: initializer.macros,
            parameters: try expand(parameters: initializer.parameters, macros: macros, context: context),
            body: try initializer.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: nil,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            }
        )
    }

    static func expand(
        derived: DerivedDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> DerivedDeclaration {
        DerivedDeclaration(
            macros: derived.macros,
            builderName: derived.builderName,
            name: derived.name,
            typeName: derived.typeName,
            body: try derived.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: nil,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            }
        )
    }

    static func expand(
        state: StateDeclaration,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> StateDeclaration {
        let storage: StateStorage

        switch state.storage {
        case .stored(let expression):
            let effects = try propertyMacroEffects(
                name: state.name,
                propertyTypeName: "State",
                propertyKind: .state,
                propertyValueType: state.type,
                applications: state.macros,
                macros: macros,
                context: context
            )
            let rewrittenExpression = applyPropertyTransforms(
                effects.initializerTransforms,
                to: expression,
            )
            storage = .stored(
                try expand(
                    expression: rewrittenExpression,
                    expectedType: state.type,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            )
        case .declared:
            storage = .declared
        }

        return StateDeclaration(
            macros: state.macros,
            name: state.name,
            hasExplicitTypeAnnotation: state.hasExplicitTypeAnnotation,
            type: state.type,
            storage: storage
        )
    }

    static func expand(
        value declaration: ValueDeclaration,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> ValueDeclaration {
        let type = try parsePropertyTypeReference(from: declaration.typeName)
        let effects = try propertyMacroEffects(
            name: declaration.name,
            propertyTypeName: "Let",
            propertyKind: .immutable,
            propertyValueType: type,
            applications: declaration.macros,
            macros: macros,
            context: context
        )

        return ValueDeclaration(
            macros: declaration.macros,
            localName: declaration.localName,
            externalLabel: declaration.externalLabel,
            typeName: declaration.typeName,
            value: try declaration.value.map {
                try expand(
                    expression: applyPropertyTransforms(effects.initializerTransforms, to: $0),
                    expectedType: type,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            }
        )
    }

    static func expand(
        binding declaration: BindingDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> BindingDeclaration {
        let storage: BindingStorage
        switch declaration.storage {
        case .plain:
            storage = .plain
        case .derived(let getterBody, let setterBody):
            storage = .derived(
                get: try expand(
                    statements: getterBody,
                    expectedReturnType: nil,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                ),
                set: try expand(
                    statements: setterBody,
                    expectedReturnType: nil,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            )
        }

        return BindingDeclaration(
            macros: declaration.macros,
            localName: declaration.localName,
            externalLabel: declaration.externalLabel,
            typeName: declaration.typeName,
            storage: storage
        )
    }

    static func propertyMacroEffects(
        states: [StateDeclaration],
        values: [ValueDeclaration],
        bindings: [BindingDeclaration],
        deriveds: [DerivedDeclaration],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> [String: PropertyMacroEffects] {
        Dictionary(
            uniqueKeysWithValues:
                try states.map {
                    (
                        $0.name,
                        try propertyMacroEffects(
                            name: $0.name,
                            propertyTypeName: "State",
                            propertyKind: .state,
                            propertyValueType: $0.type,
                            applications: $0.macros,
                            macros: macros,
                            context: context
                        )
                    )
                }
                + values.map {
                    (
                        $0.name,
                        try propertyMacroEffects(
                            name: $0.name,
                            propertyTypeName: "Let",
                            propertyKind: .immutable,
                            propertyValueType: try parsePropertyTypeReference(from: $0.typeName),
                            applications: $0.macros,
                            macros: macros,
                            context: context
                        )
                    )
                }
                + bindings.map {
                    (
                        $0.name,
                        try propertyMacroEffects(
                            name: $0.name,
                            propertyTypeName: "Binding",
                            propertyKind: .binding,
                            propertyValueType: try parsePropertyTypeReference(from: $0.typeName),
                            applications: $0.macros,
                            macros: macros,
                            context: context
                        )
                    )
                }
                + deriveds.map {
                    (
                        $0.name,
                        try propertyMacroEffects(
                            name: $0.name,
                            propertyTypeName: "Derived",
                            propertyKind: .derived,
                            propertyValueType: try parsePropertyTypeReference(from: $0.typeName),
                            applications: $0.macros,
                            macros: macros,
                            context: context
                        )
                    )
                }
        )
    }

    static func propertyMacroEffects(
        name: String,
        propertyTypeName: String,
        propertyKind: PropertyDeclarationKind,
        propertyValueType: TypeReference,
        applications: [MacroApplication],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> PropertyMacroEffects {
        var initializerTransforms: [Expression] = []
        var getterTransforms: [Expression] = []
        var setterTransforms: [Expression] = []

        for application in applications {
            guard let macro = macros[application.name] else {
                throw ParseError("Unknown attached macro @\(application.name).")
            }
            guard allowedMacroTargetKinds(for: propertyKind).contains(macroTargetKind(for: macro)) else {
                throw ParseError(
                    "Macro #\(application.name) is used on \(propertyKindDescription(propertyKind)) \(name) but targets \(macro.target.typeReference.displayName)."
                )
            }
            guard context.propertyMacroTargetMatches(
                macro,
                propertyTypeName: propertyTypeName,
                propertyValueType: propertyValueType
            ) else {
                throw ParseError(
                    "Macro #\(application.name) targeting \(macro.target.typeReference.displayName) does not match \(propertyKindDescription(propertyKind)) \(name): \(propertyValueType.displayName)."
                )
            }

            let argumentBindings = try parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )

            for registration in try propertyTransformRegistrations(for: macro) {
                guard supportedHooks(for: propertyKind).contains(registration.hook) else {
                    throw ParseError(
                        "Macro #\(application.name) uses unsupported \(propertyHookName(registration.hook)) hook on \(propertyKindDescription(propertyKind)) \(name)."
                    )
                }

                let substituted = substituteMacroBindings(
                    in: registration.body,
                    bindings: argumentBindings
                )

                switch registration.hook {
                case .initializer:
                    initializerTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [registration.parameterName: .identifier("__property_input__")]
                        )
                    )
                case .getter:
                    getterTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [registration.parameterName: .identifier("__property_input__")]
                        )
                    )
                case .setter:
                    setterTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [registration.parameterName: .identifier("__property_input__")]
                        )
                    )
                }
            }
        }

        return PropertyMacroEffects(
            kind: propertyKind,
            type: propertyValueType,
            initializerTransforms: initializerTransforms,
            getterTransforms: getterTransforms,
            setterTransforms: setterTransforms
        )
    }

    static func applyPropertyTransforms(
        _ transforms: [Expression],
        to expression: Expression
    ) -> Expression {
        transforms.reduce(expression) { current, transform in
            substituteMacroBindings(
                in: transform,
                bindings: ["__property_input__": current]
            )
        }
    }

    static func expectedType(
        for target: AssignmentTarget,
        stateEffects: [String: PropertyMacroEffects]
    ) -> TypeReference? {
        switch target {
        case .state(let name), .binding(let name):
            return stateEffects[name]?.type
        case .member(let base, _):
            return expectedType(for: base, stateEffects: stateEffects)
        case .environment, .local:
            return nil
        }
    }

    static func parsePropertyTypeReference(from raw: String) throws -> TypeReference {
        var parser = try Parser(source: raw)
        let type = try parser.parseTypeReferenceNode()
        try parser.consume(.eof)
        return type
    }

    static func allowedMacroTargetKinds(
        for propertyKind: PropertyDeclarationKind
    ) -> Set<MacroTargetKind> {
        switch propertyKind {
        case .state:
            return [.state, .property]
        case .immutable:
            return [.immutable, .property]
        case .binding:
            return [.binding, .property]
        case .derived:
            return [.derived, .property]
        }
    }

    static func supportedHooks(
        for propertyKind: PropertyDeclarationKind
    ) -> Set<PropertyTransformHook> {
        switch propertyKind {
        case .state:
            return [.initializer, .getter, .setter]
        case .immutable:
            return [.initializer, .getter]
        case .binding:
            return [.getter, .setter]
        case .derived:
            return [.getter]
        }
    }

    static func propertyKindDescription(_ propertyKind: PropertyDeclarationKind) -> String {
        switch propertyKind {
        case .state:
            return "state"
        case .immutable:
            return "let"
        case .binding:
            return "binding"
        case .derived:
            return "derived"
        }
    }

    static func propertyHookName(_ hook: PropertyTransformHook) -> String {
        switch hook {
        case .initializer:
            return "initializer"
        case .getter:
            return "getter"
        case .setter:
            return "setter"
        }
    }

    static func rewrittenPropertyAssignmentExpression(
        target: AssignmentTarget,
        expression: Expression,
        stateEffects: [String: PropertyMacroEffects]
    ) -> Expression {
        guard let name = propertyName(for: target),
            let effects = stateEffects[name],
            !effects.setterTransforms.isEmpty
        else {
            return expression
        }

        return applyPropertyTransforms(effects.setterTransforms, to: expression)
    }

    static func rewrittenPropertyReadExpression(
        _ expression: Expression,
        stateEffects: [String: PropertyMacroEffects]
    ) -> Expression {
        guard case .identifier(let name) = expression,
            let effects = stateEffects[name],
            !effects.getterTransforms.isEmpty
        else {
            return expression
        }

        return applyPropertyTransforms(effects.getterTransforms, to: expression)
    }

    static func rewrittenCompoundStateAssignment(
        target: AssignmentTarget,
        operatorSymbol: CompoundOperator,
        expression: Expression,
        stateEffects: [String: PropertyMacroEffects]
    ) -> Statement? {
        guard let name = propertyName(for: target),
            let effects = stateEffects[name],
            !effects.setterTransforms.isEmpty
        else {
            return nil
        }

        let combinedExpression: Expression
        switch operatorSymbol {
        case .plusEquals:
            combinedExpression = .binary(
                lhs: .identifier(name),
                operatorSymbol: .addition,
                rhs: expression
            )
        }

        return .assignment(
            target: target,
            expression: applyPropertyTransforms(effects.setterTransforms, to: combinedExpression)
        )
    }

    static func propertyName(for target: AssignmentTarget) -> String? {
        switch target {
        case .state(let name), .binding(let name):
            return name
        case .environment, .local, .member:
            return nil
        }
    }

    static func expand(
        statements: [Statement],
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> [Statement] {
        var expanded: [Statement] = []
        for statement in statements {
            expanded.append(
                contentsOf: try expand(
                    statement: statement,
                    expectedReturnType: expectedReturnType,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                ))
        }
        return expanded
    }

    static func expand(
        statement: Statement,
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> [Statement] {
        switch statement {
        case .expand:
            return []
        case .macroInvocation(let name, let argumentClause, let body):
            _ = argumentClause
            _ = body
            throw ParseError("Block macros like #\(name) { ... } are no longer supported.")
        case .background(let background):
            return [
                .background(
                    Background(body: try expand(
                        statements: background.body,
                        expectedReturnType: nil,
                        macros: macros,
                        protocols: protocols,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ))
                )
            ]
        case .deferBlock(let deferred):
            return [
                .deferBlock(
                    DeferredBlock(body: try expand(
                        statements: deferred.body,
                        expectedReturnType: expectedReturnType,
                        macros: macros,
                        protocols: protocols,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ))
                )
            ]
        case .localCallable(let declaration):
            return [
                .localCallable(
                    LocalCallableDeclaration(
                        macros: declaration.macros,
                        attribute: declaration.attribute,
                        name: declaration.name,
                        genericParameters: declaration.genericParameters,
                        hasExplicitParameterClause: declaration.hasExplicitParameterClause,
                        parameters: declaration.parameters,
                        returnType: declaration.returnType,
                        body: try expand(
                            statements: declaration.body,
                            expectedReturnType: declaration.returnType,
                            macros: macros,
                            protocols: protocols,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects
                        )
                    )
                )
            ]
        case .derived(let name, let typeName, let body):
            return [
                .derived(
                    name: name, typeName: typeName,
                    body: try expand(
                        statements: body,
                        macros: macros,
                        protocols: protocols,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ))
            ]
        case .forEach(let name, let sequence, let body):
            return [
                .forEach(
                    name: name,
                    sequence: try expand(
                        expression: sequence,
                        expectedType: nil,
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ),
                    body: try expand(
                        statements: body,
                        expectedReturnType: expectedReturnType,
                        macros: macros,
                        protocols: protocols,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ))
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: try expand(
                        expression: condition,
                        expectedType: .named("Bool"),
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ),
                    body: try expand(
                        statements: body,
                        expectedReturnType: expectedReturnType,
                        macros: macros,
                        protocols: protocols,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context
                    ))
            ]
        case .conditional(let branches):
            return [
                .conditional(
                    try branches.map { branch in
                        StatementConditionalBranch(
                            condition: try branch.condition.map {
                                try expand(
                                    expression: $0,
                                    expectedType: .named("Bool"),
                                    macros: macros,
                                    parameterMacroSignatures: parameterMacroSignatures,
                                    literalBridges: literalBridges,
                                    context: context,
                                    stateEffects: stateEffects)
                            },
                            body: try expand(
                                statements: branch.body,
                                expectedReturnType: expectedReturnType,
                                macros: macros,
                                protocols: protocols,
                                parameterMacroSignatures: parameterMacroSignatures,
                                literalBridges: literalBridges,
                                context: context,
                                stateEffects: stateEffects
                            )
                        )
                    }
                )
            ]
        case .localBinding(let declaration):
            return [
                .localBinding(
                    LocalBindingDeclaration(
                        kind: declaration.kind,
                        name: declaration.name,
                        hasExplicitTypeAnnotation: declaration.hasExplicitTypeAnnotation,
                        type: declaration.type,
                        expression: try expand(
                            expression: declaration.expression,
                            expectedType: declaration.hasExplicitTypeAnnotation
                                ? declaration.type : nil,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects
                        )
                    )
                )
            ]
        case .assignment(let target, let expression):
            let rewrittenExpression = rewrittenPropertyAssignmentExpression(
                target: target,
                expression: expression,
                stateEffects: stateEffects
            )
            return [
                .assignment(
                    target: target,
                    expression: try expand(
                        expression: rewrittenExpression,
                        expectedType: expectedType(for: target, stateEffects: stateEffects),
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    )
                )
            ]
        case .compoundAssignment(let target, let operatorSymbol, let expression):
            if let rewrittenAssignment = rewrittenCompoundStateAssignment(
                target: target,
                operatorSymbol: operatorSymbol,
                expression: expression,
                stateEffects: stateEffects
            ) {
                return try expand(
                    statement: rewrittenAssignment,
                    expectedReturnType: expectedReturnType,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            }

            return [
                .compoundAssignment(
                    target: target,
                    operatorSymbol: operatorSymbol,
                    expression: try expand(
                        expression: expression,
                        expectedType: nil,
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    )
                )
            ]
        case .expression(let expression):
            return [
                .expression(
                    try expand(
                        expression: expression,
                        expectedType: nil,
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context))
            ]
        case .return(let expression):
            return [
                .return(
                    try expression.map {
                        try expand(
                            expression: $0,
                            expectedType: expectedReturnType,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects)
                    })
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: try expand(
                        expression: expression,
                        expectedType: nil,
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    ),
                    cases: try cases.map { switchCase in
                        SwitchCase(
                            pattern: try expand(
                                switchCasePattern: switchCase.pattern,
                                macros: macros,
                                parameterMacroSignatures: parameterMacroSignatures,
                                literalBridges: literalBridges,
                                context: context,
                                stateEffects: stateEffects
                            ),
                            body: try expand(
                                statements: switchCase.body,
                                expectedReturnType: expectedReturnType,
                                macros: macros,
                                protocols: protocols,
                                parameterMacroSignatures: parameterMacroSignatures,
                                literalBridges: literalBridges,
                                context: context,
                                stateEffects: stateEffects
                            )
                        )
                    },
                    defaultBody: try defaultBody.map {
                        try expand(
                            statements: $0,
                            expectedReturnType: expectedReturnType,
                            macros: macros,
                            protocols: protocols,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects
                        )
                    }
                )
            ]
        default:
            return [statement]
        }
    }

    static func expand(
        switchCasePattern pattern: SwitchCasePattern,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> SwitchCasePattern {
        switch pattern {
        case .expression(let expression):
            return .expression(
                try expand(
                    expression: expression,
                    expectedType: nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            )
        case .enumCase:
            return pattern
        }
    }

    static func expand(
        parameters: [NeatFunctionParameter],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> [NeatFunctionParameter] {
        try parameters.map { parameter in
            let attachedParameterMacros: [MacroDeclaration] = parameter.macros.compactMap {
                macroApplication in
                guard let macro = macros[macroApplication.name],
                    macroTargetKind(for: macro) == .parameter
                else {
                    return nil
                }
                return macro
            }

            guard !attachedParameterMacros.isEmpty,
                let typeReference = parameter.typeReference
            else {
                return parameter
            }

            let rewrittenType = try attachedParameterMacros.reduce(typeReference) {
                currentType, macro in
                try applyAttachedParameterTypeRewrite(macro: macro, to: currentType, context: context)
            }

            return NeatFunctionParameter(
                macros: parameter.macros,
                localName: parameter.localName,
                externalLabel: parameter.externalLabel,
                typeReference: rewrittenType,
                slotName: parameter.slotName,
                isBinding: parameter.isBinding,
                capturesSyntax: parameter.capturesSyntax
            )
        }
    }

    static func expand(
        expression: Expression,
        expectedType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> Expression {
        switch expression {
        case .call(let name, let arguments):
            let rewrittenArguments = try arguments.map { argument in
                CallArgument(
                    label: argument.label,
                    value: try expand(
                        expression: argument.value,
                        expectedType: nil,
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    )
                )
            }

            let callArguments: [CallArgument]
            if let signature = try matchingParameterMacroSignature(
                name: name,
                arguments: rewrittenArguments,
                signatures: parameterMacroSignatures,
                context: context
            ) {
                var wrappedArguments: [CallArgument] = []
                var argumentIndex = 0

                for parameterIndex in signature.labels.indices {
                    if let macro = signature.parameterMacrosByIndex[parameterIndex],
                        try parameterApplicationRewritePlan(for: macro, context: context)?.isVariadic == true
                    {
                        let consumedArguments = Array(rewrittenArguments.dropFirst(argumentIndex))
                        wrappedArguments.append(
                            try applyParameterApplicationRewrite(
                                macro: macro,
                                arguments: consumedArguments,
                                context: context
                            )
                        )
                        argumentIndex = rewrittenArguments.count
                        continue
                    }

                    guard argumentIndex < rewrittenArguments.count else {
                        break
                    }

                    let argument = rewrittenArguments[argumentIndex]
                    if let macro = signature.parameterMacrosByIndex[parameterIndex] {
                        wrappedArguments.append(
                            try applyParameterApplicationRewrite(
                                macro: macro,
                                arguments: [argument],
                                context: context
                            )
                        )
                    } else {
                        wrappedArguments.append(argument)
                    }
                    argumentIndex += 1
                }
                callArguments = wrappedArguments
            } else {
                callArguments = rewrittenArguments
            }

            if let rewrittenByInitMacro = try applyInitMacroRewritesIfNeeded(
                callName: name,
                callArguments: callArguments,
                macros: macros,
                context: context
            ) {
                return rewrittenByInitMacro
            }

            if let rewrittenByFunctionMacro = try applyFunctionMacroRewritesIfNeeded(
                callName: name,
                callArguments: callArguments,
                context: context
            ) {
                return rewrittenByFunctionMacro
            }

            return .call(name: name, arguments: callArguments)
        case .macroInvocation(let name, let arguments):
            guard let macro = macros[name],
                macroTargetKind(for: macro) == .expression
            else {
                let rewrittenArguments = try arguments.map { argument in
                    CallArgument(
                        label: argument.label,
                        value: try expand(
                            expression: argument.value,
                            expectedType: nil,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects
                        )
                    )
                }
                return .macroInvocation(name: name, arguments: rewrittenArguments)
            }

            let argumentBindings = try expressionMacroArgumentBindings(
                for: macro,
                arguments: arguments
            )
            let rewrite = try rewriteExpression(for: macro, context: context)
            let interpreted = interpretExpressionMacroRewrite(rewrite, bindings: argumentBindings)
            let substituted = substituteMacroBindings(in: interpreted, bindings: argumentBindings)
            return try expand(
                expression: substituted,
                expectedType: expectedType,
                macros: macros,
                parameterMacroSignatures: parameterMacroSignatures,
                literalBridges: literalBridges,
                context: context,
                stateEffects: stateEffects
            )
        case .array(let elements):
            return .array(
                try elements.map {
                    try expand(
                        expression: $0,
                        expectedType: nil,
                        macros: macros,
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    )
                }
            )
        case .dictionary(let elements):
            return .dictionary(
                try elements.map { element in
                    DictionaryElement(
                        key: try expand(
                            expression: element.key,
                            expectedType: nil,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects
                        ),
                        value: try expand(
                            expression: element.value,
                            expectedType: nil,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: stateEffects
                        )
                    )
                }
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            return .ternary(
                condition: try expand(
                    expression: condition,
                    expectedType: .named("Bool"),
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects),
                trueExpression: try expand(
                    expression: trueExpression,
                    expectedType: expectedType,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                ),
                falseExpression: try expand(
                    expression: falseExpression,
                    expectedType: expectedType,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            )
        case .unary(let operatorSymbol, let nested):
            return .unary(
                operatorSymbol: operatorSymbol,
                expression: try expand(
                    expression: nested,
                    expectedType: operatorSymbol == .not ? .named("Bool") : nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: try expand(
                    expression: lhs,
                    expectedType: nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects),
                operatorSymbol: operatorSymbol,
                rhs: try expand(
                    expression: rhs,
                    expectedType: nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects)
            )
        case .interpolatedString(let string):
            let expanded: Expression = .interpolatedString(
                InterpolatedString(
                    segments: try string.segments.map { segment in
                        switch segment {
                        case .text:
                            return segment
                        case .expression(let nested):
                            return .expression(
                                try expand(
                                    expression: nested,
                                    expectedType: nil,
                                    macros: macros,
                                    parameterMacroSignatures: parameterMacroSignatures,
                                    literalBridges: literalBridges,
                                    context: context,
                                    stateEffects: stateEffects
                                ))
                        }
                    }
                )
            )
            return try lowerLiteralExpressionIfPossible(
                expanded,
                expectedType: expectedType,
                macros: macros,
                literalBridges: literalBridges,
                context: context
            )
        case .block(let body):
            return .block(
                try body.flatMap {
                    try expand(
                        statement: $0,
                        expectedReturnType: nil,
                        macros: macros,
                        protocols: [:],
                        parameterMacroSignatures: parameterMacroSignatures,
                        literalBridges: literalBridges,
                        context: context,
                        stateEffects: stateEffects
                    )
                }
            )
        case .integer, .double, .string, .boolean, .nilLiteral:
            return try lowerLiteralExpressionIfPossible(
                expression,
                expectedType: expectedType,
                macros: macros,
                literalBridges: literalBridges,
                context: context
            )
        case .identifier:
            return rewrittenPropertyReadExpression(expression, stateEffects: stateEffects)
        case .bindingReference:
            return expression
        }
    }

    static func emittedDeclarations(
        from construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> EmittedDeclarationBundle {
        var emitted = EmittedDeclarationBundle()

        for application in construct.macros {
            guard let macro = macros[application.name], macroTargetKind(for: macro) == .construct else {
                continue
            }
            emitted.merge(try emittedDeclarations(from: macro, construct: construct, context: context))
        }

        for nested in construct.constructs {
            let nestedEmitted = try emittedDeclarations(
                from: nested,
                macros: macros,
                context: context
            )
            guard
                nestedEmitted.states.isEmpty
                    && nestedEmitted.namespaces.isEmpty
                    && nestedEmitted.enumerations.isEmpty
                    && nestedEmitted.protocols.isEmpty
                    && nestedEmitted.extensions.isEmpty
            else {
                throw ParseError(
                    "Nested construct macros can currently emit peer callables and constructs only in this bootstrap pass."
                )
            }
            emitted.callables.append(contentsOf: nestedEmitted.callables)
            emitted.constructs.append(contentsOf: nestedEmitted.constructs)
        }

        return emitted
    }

    static func emittedDeclarations(
        from macro: MacroDeclaration,
        construct: ConstructDeclaration,
        context: MacroExpansionContext
    ) throws -> EmittedDeclarationBundle {
        var emitted = EmittedDeclarationBundle()

        for block in emittedCodeBlocks(in: macro.body) {
            emitted.merge(
                try emittedDeclarationBundle(
                    from: block,
                    macro: macro,
                    construct: construct,
                    context: context
                )
            )
        }

        return emitted
    }

    static func emittedCodeBlocks(in statements: [Statement]) -> [EmittedCodeBlock] {
        var blocks: [EmittedCodeBlock] = []

        for statement in statements {
            switch statement {
            case .expand(let emitted):
                blocks.append(emitted)
            case .conditional(let branches):
                for branch in branches {
                    blocks.append(contentsOf: emittedCodeBlocks(in: branch.body))
                }
            case .whileLoop(_, let body), .forEach(_, _, let body), .derived(_, _, let body):
                blocks.append(contentsOf: emittedCodeBlocks(in: body))
            case .background(let background):
                blocks.append(contentsOf: emittedCodeBlocks(in: background.body))
            case .deferBlock(let deferred):
                blocks.append(contentsOf: emittedCodeBlocks(in: deferred.body))
            case .localCallable(let declaration):
                blocks.append(contentsOf: emittedCodeBlocks(in: declaration.body))
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    blocks.append(contentsOf: emittedCodeBlocks(in: switchCase.body))
                }
                if let defaultBody {
                    blocks.append(contentsOf: emittedCodeBlocks(in: defaultBody))
                }
            case .macroInvocation, .localBinding, .assignment, .compoundAssignment, .expression,
                .return, .environmentProvision, .break, .continue:
                continue
            }
        }

        return blocks
    }

    static func emittedDeclarationBundle(
        from block: EmittedCodeBlock,
        macro: MacroDeclaration,
        construct: ConstructDeclaration,
        context: MacroExpansionContext
    ) throws -> EmittedDeclarationBundle {
        let rendered = try renderEmittedCodeBlock(
            block,
            macro: macro,
            construct: construct,
            context: context
        )

        var parser = try Parser(source: rendered)
        let sourceFile = try parser.parseSourceFile()
        return try declarationBundle(from: sourceFile)
    }

    static func renderEmittedCodeBlock(
        _ block: EmittedCodeBlock,
        macro: MacroDeclaration,
        construct: ConstructDeclaration,
        context: MacroExpansionContext
    ) throws -> String {
        let targetSurface = MacroTargetSurface(
            targetBinding: macro.bindings.target,
            targetType: macro.target.typeReference,
            construct: construct,
            context: context
        )

        return try block.parts.map { part in
            switch part {
            case .text(let text):
                return text
            case .splice(let expression, let expected):
                let actual = targetSurface.emittedSyntaxKinds(of: expression)
                guard emittedSyntaxKind(actual, isCompatibleWith: expected) else {
                    throw ParseError(
                        "Interpolation in \(emittedSyntaxPositionDescription(expected)) position must produce \(expected.diagnosticDescription), got \(emittedSyntaxDescription(actual))."
                    )
                }
                let substituted = targetSurface.render(expression)
                if (expected == .callableName || expected == .declaration),
                    case .string(let name) = substituted
                {
                    return name
                }
                return renderExpressionForStringify(substituted)
            }
        }.joined(separator: " ")
    }

    static func emittedSyntaxKind(
        _ actual: Set<EmittedSyntaxKind>,
        isCompatibleWith expected: EmittedSyntaxKind
    ) -> Bool {
        if expected == .expression {
            return true
        }
        return actual.contains(expected)
    }

    static func emittedSyntaxDescription(_ kinds: Set<EmittedSyntaxKind>) -> String {
        kinds.sorted { $0.rawValue < $1.rawValue }
            .map(\.diagnosticDescription)
            .joined(separator: " or ")
    }

    static func emittedSyntaxPositionDescription(_ kind: EmittedSyntaxKind) -> String {
        switch kind {
        case .declaration:
            return "declaration"
        case .expression:
            return "expression"
        case .typeReference:
            return "type reference"
        case .nominalTypeReference:
            return "nominal type reference"
        case .callableName:
            return "function name"
        }
    }

    static func declarationBundle(from sourceFile: SourceFileNode) throws -> EmittedDeclarationBundle {
        switch sourceFile {
        case .construct(let declaration):
            return EmittedDeclarationBundle(constructs: [declaration])
        case .namespace(let declaration):
            return EmittedDeclarationBundle(namespaces: [declaration])
        case .enumeration(let declaration):
            return EmittedDeclarationBundle(enumerations: [declaration])
        case .protocolDefinition(let declaration):
            return EmittedDeclarationBundle(protocols: [declaration])
        case .extensions(let declarations):
            return EmittedDeclarationBundle(extensions: declarations)
        case .module(let module):
            return EmittedDeclarationBundle(
                states: module.states,
                callables: module.callables,
                constructs: module.constructs,
                namespaces: module.namespaces,
                enumerations: module.enumerations,
                protocols: module.protocols,
                extensions: module.extensions
            )
        case .mainBlock:
            throw ParseError("Macros cannot emit @main blocks.")
        case .macro:
            throw ParseError("Macros cannot emit macro declarations.")
        }
    }
}
