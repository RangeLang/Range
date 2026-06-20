extension MacroExpander {
    struct EmittedDeclarationBundle {
        var states: [StateDeclaration] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var macros: [MacroDeclaration] = []
        var extensions: [ExtensionDeclaration] = []

        var isEmpty: Bool {
            states.isEmpty
                && callables.isEmpty
                && constructs.isEmpty
                && enumerations.isEmpty
                && macros.isEmpty
                && extensions.isEmpty
        }

        mutating func merge(_ other: EmittedDeclarationBundle) {
            states.append(contentsOf: other.states)
            callables.append(contentsOf: other.callables)
            constructs.append(contentsOf: other.constructs)
            enumerations.append(contentsOf: other.enumerations)
            macros.append(contentsOf: other.macros)
            extensions.append(contentsOf: other.extensions)
        }
    }

    static func expand(
        sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext
    ) throws -> SourceFileNode {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .mainBlock(
                MainBlockNode(
                    macros: mainBlock.macros,
                    body: try expandMainBlockBody(
                        mainBlock,
                        expectedReturnType: nil,
                        macros: macros,
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
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
                )
            }
            let emittedDeclarationBundles =
                try module.constructs.map {
                    try emittedDeclarations(from: $0, macros: macros, context: context)
                }
                + module.enumerations.map {
                    try emittedDeclarations(from: $0, macros: macros, context: context)
                }
            let expandedExtensions = try module.extensions.map {
                try expand(extensionDeclaration: $0, macros: macros, context: context)
            }
            return .module(
                ModuleFileNode(
                    mainBlock: try module.mainBlock.map {
                        MainBlockNode(
                            macros: $0.macros,
                            body: try expandMainBlockBody(
                                $0,
                                expectedReturnType: nil,
                                macros: macros,
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
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context,
                            stateEffects: moduleStateEffects
                        )
                    } + emittedDeclarationBundles.flatMap(\.callables),
                    constructs: expandedConstructs
                        + emittedDeclarationBundles.flatMap(\.constructs),
                    enumerations: module.enumerations
                        + emittedDeclarationBundles.flatMap(\.enumerations),
                    macros: module.macros + emittedDeclarationBundles.flatMap(\.macros),
                    precedenceGroups: module.precedenceGroups,
                    operators: module.operators,
                    extensions: expandedExtensions + emittedDeclarationBundles.flatMap(\.extensions)
                )
            )
        case .construct(let declaration):
            let expandedConstruct = try expand(
                construct: declaration,
                macros: macros,
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
                    || !emittedBundle.enumerations.isEmpty
                    || !emittedBundle.macros.isEmpty
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
                    enumerations: emittedBundle.enumerations,
                    macros: emittedBundle.macros,
                    precedenceGroups: [],
                    operators: [],
                    extensions: emittedBundle.extensions
                )
            )
        case .enumeration(let declaration):
            let emittedBundle = try emittedDeclarations(
                from: declaration,
                macros: macros,
                context: context
            )
            guard !emittedBundle.isEmpty else {
                return sourceFile
            }
            return .module(
                ModuleFileNode(
                    mainBlock: nil,
                    states: emittedBundle.states,
                    callables: emittedBundle.callables,
                    constructs: emittedBundle.constructs,
                    enumerations: [declaration] + emittedBundle.enumerations,
                    macros: emittedBundle.macros,
                    precedenceGroups: [],
                    operators: [],
                    extensions: emittedBundle.extensions
                )
            )
        case .extensions(let declarations):
            return .extensions(
                try declarations.map {
                    try expand(extensionDeclaration: $0, macros: macros, context: context)
                }
            )
        case .macro:
            return sourceFile
        }
    }

    static func expandMainBlockBody(
        _ mainBlock: MainBlockNode,
        expectedReturnType: TypeReference?,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> [Statement] {
        let expandedBody = try expand(
            statements: mainBlock.body,
            expectedReturnType: expectedReturnType,
            macros: macros,
            parameterMacroSignatures: parameterMacroSignatures,
            literalBridges: literalBridges,
            context: context,
            stateEffects: stateEffects
        )

        try emitMainBlockMacroDiagnostics(
            mainBlock,
            macros: macros,
            context: context,
            targetValue: blockMacroTargetValue(expandedBody)
        )

        guard let application = mainBlock.macros.first,
            let macro = macros[application.name],
            let bindings = macro.bindings
        else {
            return expandedBody
        }

        guard let rewriteBody = try optionalRewriteBody(for: macro, context: context) else {
            return expandedBody
        }

        let rewritten = substituteMacroTargetCalls(
            in: rewriteBody,
            targetBinding: bindings.target,
            targetBlock: expandedBody
        )

        return try expand(
            statements: rewritten,
            expectedReturnType: expectedReturnType,
            macros: macros,
            parameterMacroSignatures: parameterMacroSignatures,
            literalBridges: literalBridges,
            context: context,
            stateEffects: stateEffects
        )
    }

    static func emitMainBlockMacroDiagnostics(
        _ mainBlock: MainBlockNode,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext,
        targetValue: CompileTimeValue? = nil
    ) throws {
        try emitBlockMacroDiagnostics(
            applications: mainBlock.macros,
            declarationName: "@main",
            macros: macros,
            context: context,
            targetValue: targetValue ?? blockMacroTargetValue(mainBlock.body)
        )
    }

    static func emitBlockMacroDiagnostics(
        applications: [MacroApplication],
        declarationName: String,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext,
        targetValue: CompileTimeValue? = nil
    ) throws {
        try emitTargetMacroDiagnostics(
            applications: applications,
            declarationName: declarationName,
            targetKind: .block,
            macros: macros,
            context: context,
            targetValue: targetValue ?? blockMacroTargetValue([])
        )
    }

    static func emitTargetMacroDiagnostics(
        applications: [MacroApplication],
        declarationName: String,
        targetKind: MacroTargetKind,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext,
        targetValue: CompileTimeValue
    ) throws {
        for application in applications {
            guard let macro = macros[application.name] else {
                throw ParseError("Unknown attached macro @\(application.name).")
            }
            guard
                macroTargetAllows(
                    macro.target!, kind: targetKind,
                    syntaxResolver: context.rewriteSurfaceView.syntaxResolver)
            else {
                throw ParseError(
                    "Macro @\(application.name) is used on \(declarationName) but targets \(macro.target!.displayName)."
                )
            }
            try emitMacroDiagnostics(
                from: macro.body,
                macro: macro,
                targetValue: targetValue,
                context: context
            )
        }
    }

    static func blockMacroTargetValue(_ statements: [Statement]) -> CompileTimeValue {
        let statementValues = statements.map { statement in
            _ = statement
            return CompileTimeValue.string("")
        }
        return .object(
            typeName: "Block",
            fields: [
                "declaration": .object(
                    typeName: "Block.Declaration",
                    fields: [
                        "body": .array(statementValues),
                        "statements": .array(statementValues),
                    ]
                ),
                "body": .array(statementValues),
                "statements": .array(statementValues),
            ]
        )
    }

    static func expand(
        extensionDeclaration: ExtensionDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> ExtensionDeclaration {
        try validateExtensionMacros(
            extensionDeclaration: extensionDeclaration,
            applications: extensionDeclaration.macros,
            macros: macros,
            context: context
        )

        return extensionDeclaration
    }

    // Evaluates a construct-attached metadata macro and, when it returns a
    // string, carries that processed result on the application so emission can
    // consume the macro's Range-authored output instead of the raw argument.
    static func attachingEvaluatedStringValue(
        to application: MacroApplication,
        construct: ConstructDeclaration,
        context: MacroExpansionContext
    ) -> MacroApplication {
        // Any construct-targeting macro that returns a String has its evaluated
        // output carried here, so emission consumes the macro's processed result.
        // Not bound to specific macro names.
        guard let metadata = context.macroMetadataByName[application.name],
            !metadata.valueType.isMacroMetadataEffect,
            metadata.valueType == .named("String")
        else {
            return application
        }
        let targetValue = MacroTargetValueBuilder(
            macroMetadataByName: context.macroMetadataByName,
            extensionsByTargetName: context.graphContext.extensionsByTargetName
        ).targetValue(for: construct)
        guard
            let value = try? MacroTargetValueBuilder.evaluateMacroMetadataValue(
                for: application,
                metadata: metadata,
                targetValue: targetValue,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
                context: context
            ),
            case .string(let processed) = value
        else {
            return application
        }
        var updated = application
        updated.evaluatedStringValue = processed
        return updated
    }

    static func expand(
        construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext
    ) throws -> ConstructDeclaration {
        try validateConstructMacros(
            construct: construct,
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

        let macrosWithValues = construct.macros.map { application in
            attachingEvaluatedStringValue(
                to: application,
                construct: construct,
                context: context
            )
        }

        return ConstructDeclaration(
            macros: macrosWithValues,
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
            bindings: try construct.bindings.map {
                try expand(
                    binding: $0,
                    macros: macros,
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
            initializers: try construct.initializers.map {
                try expand(
                    initializer: $0,
                    macros: macros,
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
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> CallableDeclaration {
        CallableDeclaration(
            macros: callable.macros,
            attribute: callable.attribute,
            targetType: callable.targetType,
            receiverType: callable.receiverType,
            name: callable.name,
            genericParameters: callable.genericParameters,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: try expand(
                parameters: callable.parameters, macros: macros, context: context),
            returnType: callable.returnType,
            body: try callable.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: callable.returnType,
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
        initializer: InitializerDeclaration,
        macros: [String: MacroDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: PropertyMacroEffects] = [:]
    ) throws -> InitializerDeclaration {
        InitializerDeclaration(
            macros: initializer.macros,
            parameters: try expand(
                parameters: initializer.parameters, macros: macros, context: context),
            returnType: initializer.returnType,
            body: try initializer.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: nil,
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
        derived: DerivedDeclaration,
        macros: [String: MacroDeclaration],
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
            name: declaration.name,
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
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                ),
                set: try expand(
                    statements: setterBody,
                    expectedReturnType: nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context,
                    stateEffects: stateEffects
                )
            )
        }

        return BindingDeclaration(
            macros: declaration.macros,
            name: declaration.name,
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
            if let metadata = context.macroMetadataByName[application.name],
                macroTargetAllowsAny(
                    metadata.target,
                    kinds: allowedMacroTargetKinds(for: propertyKind),
                    syntaxResolver: context.rewriteSurfaceView.syntaxResolver
                ),
                context.propertyMacroMetadataTargetMatches(
                    metadata,
                    propertyTypeName: propertyTypeName,
                    propertyValueType: propertyValueType
                )
            {
                let argumentBindings = try parseMacroMetadataArgumentBindings(
                    for: metadata,
                    argumentClause: application.argumentClause,
                    rawBody: application.rawBody
                )
                let genericBindings = macroMetadataGenericArgumentBindings(
                    for: metadata,
                    application: application
                )
                let targetValue = macroMetadataTargetValue(
                    kind: propertyKindDescription(propertyKind),
                    name: name
                )
                try emitMacroMetadataDiagnostics(
                    from: metadata.body,
                    metadata: metadata,
                    targetValue: targetValue,
                    context: context,
                    localBindings: argumentBindings.merging(genericBindings) { _, generic in generic
                    }
                )
                if metadata.valueType.isMacroMetadataEffect {
                    continue
                }
                _ = try MacroTargetValueBuilder.evaluateMacroMetadataValue(
                    for: application,
                    metadata: metadata,
                    targetValue: targetValue,
                    knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
                    context: context
                )
                continue
            }

            guard let macro = macros[application.name] else {
                if let metadata = context.macroMetadataByName[application.name] {
                    guard
                        macroTargetAllowsAny(
                            metadata.target,
                            kinds: allowedMacroTargetKinds(for: propertyKind),
                            syntaxResolver: context.rewriteSurfaceView.syntaxResolver
                        )
                    else {
                        throw ParseError(
                            "Macro @\(application.name) is used on \(propertyKindDescription(propertyKind)) \(name) but targets \(metadata.target.displayName)."
                        )
                    }
                    guard
                        context.propertyMacroMetadataTargetMatches(
                            metadata,
                            propertyTypeName: propertyTypeName,
                            propertyValueType: propertyValueType
                        )
                    else {
                        throw ParseError(
                            "Macro @\(application.name) targeting \(metadata.target.displayName) does not match \(propertyKindDescription(propertyKind)) \(name): \(propertyValueType.displayName)."
                        )
                    }
                    let argumentBindings = try parseMacroMetadataArgumentBindings(
                        for: metadata,
                        argumentClause: application.argumentClause,
                        rawBody: application.rawBody
                    )
                    let genericBindings = macroMetadataGenericArgumentBindings(
                        for: metadata,
                        application: application
                    )
                    let targetValue = macroMetadataTargetValue(
                        kind: propertyKindDescription(propertyKind),
                        name: name
                    )
                    try emitMacroMetadataDiagnostics(
                        from: metadata.body,
                        metadata: metadata,
                        targetValue: targetValue,
                        context: context,
                        localBindings: argumentBindings.merging(genericBindings) { _, generic in
                            generic
                        }
                    )
                    if metadata.valueType.isMacroMetadataEffect {
                        continue
                    }
                    _ = try MacroTargetValueBuilder.evaluateMacroMetadataValue(
                        for: application,
                        metadata: metadata,
                        targetValue: targetValue,
                        knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
                        context: context
                    )
                    continue
                }
                if application.name == "Parsed" {
                    continue
                }
                throw ParseError("Unknown attached macro @\(application.name).")
            }
            guard
                macroTargetAllowsAny(
                    macro.target!,
                    kinds: allowedMacroTargetKinds(for: propertyKind),
                    syntaxResolver: context.rewriteSurfaceView.syntaxResolver
                )
            else {
                throw ParseError(
                    "Macro @\(application.name) is used on \(propertyKindDescription(propertyKind)) \(name) but targets \(macro.target!.displayName)."
                )
            }
            guard
                context.propertyMacroTargetMatches(
                    macro,
                    propertyTypeName: propertyTypeName,
                    propertyValueType: propertyValueType
                )
            else {
                throw ParseError(
                    "Macro @\(application.name) targeting \(macro.target!.displayName) does not match \(propertyKindDescription(propertyKind)) \(name): \(propertyValueType.displayName)."
                )
            }

            let argumentBindings = try parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )
            let genericBindings = macroGenericArgumentBindings(
                for: macro,
                application: application
            )
            let localBindings = argumentBindings.merging(genericBindings) { _, generic in generic }
            try emitMacroDiagnostics(
                from: substituteMacroBindings(in: macro.body, bindings: localBindings),
                macro: macro,
                context: context,
                localBindings: localBindings
            )

            for registration in try propertyTransformRegistrations(for: macro) {
                guard supportedHooks(for: propertyKind).contains(registration.hook) else {
                    throw ParseError(
                        "Macro @\(application.name) uses unsupported \(propertyHookName(registration.hook)) hook on \(propertyKindDescription(propertyKind)) \(name)."
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
                            bindings: [
                                registration.parameterName: .identifier("__property_input__")
                            ]
                        )
                    )
                case .getter:
                    getterTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [
                                registration.parameterName: .identifier("__property_input__")
                            ]
                        )
                    )
                case .setter:
                    setterTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [
                                registration.parameterName: .identifier("__property_input__")
                            ]
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
        case .local:
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

    static func macroMetadataTargetValue(kind: String, name: String) -> CompileTimeValue {
        .object(
            typeName: "Macro.Target",
            fields: [
                "identity": MacroTargetValueBuilder().graphIdentity(kind: kind, name: name)
            ]
        )
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
        case .local, .member:
            return nil
        }
    }

    static func expand(
        statements: [Statement],
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
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
            let expandedBody = try expand(
                statements: background.body,
                expectedReturnType: nil,
                macros: macros,
                parameterMacroSignatures: parameterMacroSignatures,
                literalBridges: literalBridges,
                context: context,
                stateEffects: stateEffects
            )
            try emitBlockMacroDiagnostics(
                applications: background.macros,
                declarationName: "@background",
                macros: macros,
                context: context,
                targetValue: blockMacroTargetValue(expandedBody)
            )
            guard let application = background.macros.first,
                let macro = macros[application.name],
                let bindings = macro.bindings
            else {
                throw ParseError("Unknown attached macro @background.")
            }
            let rewritten = substituteMacroTargetCalls(
                in: try rewriteBody(for: macro, context: context),
                targetBinding: bindings.target,
                targetBlock: expandedBody
            )
            return try expand(
                statements: rewritten,
                expectedReturnType: nil,
                macros: macros,
                parameterMacroSignatures: parameterMacroSignatures,
                literalBridges: literalBridges,
                context: context,
                stateEffects: stateEffects
            )
        case .deferBlock(let deferred):
            return [
                .deferBlock(
                    DeferredBlock(
                        body: try expand(
                            statements: deferred.body,
                            expectedReturnType: expectedReturnType,
                            macros: macros,
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
        parameters: [RangeFunctionParameter],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> [RangeFunctionParameter] {
        try parameters.map { parameter in
            let attachedParameterMacros: [MacroDeclaration] = parameter.macros.compactMap {
                macroApplication in
                guard let macro = macros[macroApplication.name],
                    macroTargetAllows(
                        macro.target!, kind: .parameter,
                        syntaxResolver: context.rewriteSurfaceView.syntaxResolver)
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
                try applyAttachedParameterTypeRewrite(
                    macro: macro, to: currentType, context: context)
            }

            return RangeFunctionParameter(
                macros: parameter.macros,
                name: parameter.localName,
                typeReference: rewrittenType,
                defaultValue: parameter.defaultValue,
                slotName: parameter.slotName,
                isBinding: parameter.isBinding,
                capturesSyntax: parameter.capturesSyntax,
                captureMetadataType: parameter.captureMetadataType
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
                        try parameterApplicationRewritePlan(for: macro, context: context)?
                            .isVariadic == true
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
                let target = macro.target,
                macroTargetAllows(
                    target, kind: .expression,
                    syntaxResolver: context.rewriteSurfaceView.syntaxResolver)
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
            try emitMacroDiagnostics(
                from: substituteMacroBindings(in: macro.body, bindings: argumentBindings),
                macro: macro,
                context: context
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
            guard let macro = macros[application.name],
                macroTargetAllows(
                    macro.target!, kind: .construct,
                    syntaxResolver: context.rewriteSurfaceView.syntaxResolver)
            else {
                continue
            }
            let argumentBindings = try parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )
            let genericBindings = macroGenericArgumentBindings(
                for: macro,
                application: application
            )
            emitted.merge(
                try emittedDeclarations(
                    from: macro,
                    construct: construct,
                    context: context,
                    argumentBindings: argumentBindings.merging(genericBindings) { _, generic in
                        generic
                    }
                )
            )
        }

        for nested in construct.constructs {
            let nestedEmitted = try emittedDeclarations(
                from: nested,
                macros: macros,
                context: context
            )
            guard
                nestedEmitted.states.isEmpty
                    && nestedEmitted.enumerations.isEmpty
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
        from enumeration: EnumDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> EmittedDeclarationBundle {
        var emitted = EmittedDeclarationBundle()

        for application in enumeration.macros {
            guard let macro = macros[application.name],
                macroTargetAllows(
                    macro.target!, kind: .enumeration,
                    syntaxResolver: context.rewriteSurfaceView.syntaxResolver)
            else {
                continue
            }
            emitted.merge(
                try emittedDeclarations(
                    from: macro,
                    targetValue: MacroTargetValueBuilder(
                        macroMetadataByName: context.macroMetadataByName,
                        writtenSyntaxByID: context.graphContext.writtenSyntaxByID
                    ).targetValue(for: enumeration),
                    context: context
                )
            )
        }

        return emitted
    }

    static func emittedDeclarations(
        from macro: MacroDeclaration,
        construct: ConstructDeclaration,
        context: MacroExpansionContext,
        argumentBindings: [String: Expression] = [:]
    ) throws -> EmittedDeclarationBundle {
        try emittedDeclarations(
            from: macro,
            targetValue: MacroTargetValueBuilder(
                macroMetadataByName: context.macroMetadataByName,
                writtenSyntaxByID: context.graphContext.writtenSyntaxByID,
                extensionsByTargetName: context.graphContext.extensionsByTargetName
            ).targetValue(for: construct),
            context: context,
            argumentBindings: argumentBindings
        )
    }

    static func emittedDeclarations(
        from macro: MacroDeclaration,
        targetValue: CompileTimeValue,
        context: MacroExpansionContext,
        argumentBindings: [String: Expression] = [:]
    ) throws -> EmittedDeclarationBundle {
        var emitted = EmittedDeclarationBundle()

        let body = substituteMacroBindings(in: macro.body, bindings: argumentBindings)
        try emitMacroDiagnostics(
            from: body,
            macro: macro,
            targetValue: targetValue,
            context: context
        )

        for (targetPath, block, localBindings) in emittedCodeBlocks(in: body) {
            if let targetPath {
                try context.validateExpansionPath(targetPath, for: macro)
            }
            emitted.merge(
                try emittedDeclarationBundle(
                    from: block,
                    macro: macro,
                    targetValue: targetValue,
                    localBindings: localBindings,
                    context: context
                )
            )
        }

        return emitted
    }

    static func emittedCodeBlocks(in statements: [Statement]) -> [(
        targetPath: String?, block: EmittedCodeBlock, localBindings: [String: Expression]
    )] {
        var blocks:
            [(targetPath: String?, block: EmittedCodeBlock, localBindings: [String: Expression])] =
                []
        var localBindings: [String: Expression] = [:]

        for statement in statements {
            switch statement {
            case .localBinding(let declaration):
                localBindings[declaration.name] = declaration.expression
            case .expand(let targetPath, let emitted):
                blocks.append((targetPath, emitted, localBindings))
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
            case .macroInvocation, .assignment, .compoundAssignment, .expression,
                .return, .break, .continue:
                continue
            }
        }

        return blocks
    }

    static func emitMacroDiagnostics(
        from statements: [Statement],
        macro: MacroDeclaration,
        targetValue: CompileTimeValue? = nil,
        context: MacroExpansionContext,
        localBindings: [String: Expression] = [:]
    ) throws {
        guard let bindings = macro.bindings else {
            return
        }
        try emitDiagnostics(
            from: statements,
            diagnosticOwnerName: macro.name,
            bindings: bindings,
            targetValue: targetValue,
            context: context,
            localBindings: localBindings
        )
    }

    static func emitMacroMetadataDiagnostics(
        from statements: [Statement],
        metadata: MacroMetadataDeclaration,
        targetValue: CompileTimeValue? = nil,
        context: MacroExpansionContext,
        localBindings: [String: Expression] = [:]
    ) throws {
        guard let bindings = metadata.bindings else {
            return
        }
        try emitDiagnostics(
            from: statements,
            diagnosticOwnerName: metadata.name,
            bindings: bindings,
            targetValue: targetValue,
            context: context,
            localBindings: localBindings
        )
    }

    private static func emitDiagnostics(
        from statements: [Statement],
        diagnosticOwnerName: String,
        bindings: MacroBindings,
        targetValue: CompileTimeValue?,
        context: MacroExpansionContext,
        localBindings: [String: Expression] = [:]
    ) throws {
        let diagnostics = try macroDiagnostics(
            in: statements,
            diagnosticOwnerName: diagnosticOwnerName,
            diagnosticsBinding: bindings.diagnostics,
            targetBinding: bindings.target,
            targetValue: targetValue,
            graphBinding: bindings.graph,
            context: context,
            localBindings: localBindings
        )
        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error:
                if let engine = context.diagnosticEngine {
                    engine.emit(diagnostic.withPath(context.currentPath))
                } else {
                    throw ParseError(diagnostic.message)
                }
            case .warning, .information, .hint:
                context.diagnosticEngine?.emit(diagnostic.withPath(context.currentPath))
            }
        }
    }

    static func macroDiagnostics(
        in statements: [Statement],
        diagnosticOwnerName: String,
        diagnosticsBinding: String,
        targetBinding: String,
        targetValue: CompileTimeValue?,
        graphBinding: String?,
        context: MacroExpansionContext,
        localBindings: [String: Expression]
    ) throws -> [RangeDiagnostic] {
        try macroDiagnosticsAndLocals(
            in: statements,
            diagnosticOwnerName: diagnosticOwnerName,
            diagnosticsBinding: diagnosticsBinding,
            targetBinding: targetBinding,
            targetValue: targetValue,
            graphBinding: graphBinding,
            context: context,
            localBindings: localBindings
        ).diagnostics
    }

    private static func macroDiagnosticsAndLocals(
        in statements: [Statement],
        diagnosticOwnerName: String,
        diagnosticsBinding: String,
        targetBinding: String,
        targetValue: CompileTimeValue?,
        graphBinding: String?,
        context: MacroExpansionContext,
        localBindings: [String: Expression]
    ) throws -> (diagnostics: [RangeDiagnostic], locals: [String: Expression]) {
        var diagnostics: [RangeDiagnostic] = []
        var locals = localBindings

        for statement in statements {
            switch statement {
            case .localBinding(let declaration):
                let evaluator = CompileTimeValueEvaluator(
                    targetBinding: targetBinding,
                    targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                    graphBinding: graphBinding,
                    selfValue: macroSelfValue(named: diagnosticOwnerName),
                    localBindings: locals,
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    context: context
                )
                locals[declaration.name] =
                    evaluator.evaluate(declaration.expression, with: locals)?.expression
                    ?? declaration.expression
            case .expression(let expression):
                if let diagnostic = try macroDiagnostic(
                    from: expression,
                    diagnosticOwnerName: diagnosticOwnerName,
                    diagnosticsBinding: diagnosticsBinding,
                    targetBinding: targetBinding,
                    targetValue: targetValue,
                    graphBinding: graphBinding,
                    context: context,
                    localBindings: locals
                ) {
                    diagnostics.append(diagnostic)
                }
            case .conditional(let branches):
                let evaluator = CompileTimeValueEvaluator(
                    targetBinding: targetBinding,
                    targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                    graphBinding: graphBinding,
                    selfValue: macroSelfValue(named: diagnosticOwnerName),
                    localBindings: locals,
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    context: context
                )
                for branch in branches {
                    if let condition = branch.condition {
                        guard case .boolean(true) = evaluator.evaluate(condition, with: locals)
                        else {
                            continue
                        }
                    }
                    let branchResult = try macroDiagnosticsAndLocals(
                        in: branch.body,
                        diagnosticOwnerName: diagnosticOwnerName,
                        diagnosticsBinding: diagnosticsBinding,
                        targetBinding: targetBinding,
                        targetValue: targetValue,
                        graphBinding: graphBinding,
                        context: context,
                        localBindings: locals
                    )
                    diagnostics.append(contentsOf: branchResult.diagnostics)
                    locals = branchResult.locals
                    break
                }
            case .whileLoop(let condition, let body):
                var iterationCount = 0
                while true {
                    let evaluator = CompileTimeValueEvaluator(
                        targetBinding: targetBinding,
                        targetValue: targetValue
                            ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                        graphBinding: graphBinding,
                        selfValue: macroSelfValue(named: diagnosticOwnerName),
                        localBindings: locals,
                        macroDeclarationsByName: context.macroDeclarationsByName,
                        context: context
                    )
                    guard case .boolean(true) = evaluator.evaluate(condition, with: locals) else {
                        break
                    }
                    guard iterationCount < 10_000 else {
                        throw ParseError(
                            "Macro @\(diagnosticOwnerName) diagnostic loop exceeded 10000 iterations."
                        )
                    }
                    let bodyResult = try macroDiagnosticsAndLocals(
                        in: body,
                        diagnosticOwnerName: diagnosticOwnerName,
                        diagnosticsBinding: diagnosticsBinding,
                        targetBinding: targetBinding,
                        targetValue: targetValue,
                        graphBinding: graphBinding,
                        context: context,
                        localBindings: locals
                    )
                    diagnostics.append(contentsOf: bodyResult.diagnostics)
                    locals = bodyResult.locals
                    iterationCount += 1
                }
            case .forEach(_, _, let body), .derived(_, _, let body):
                let bodyResult = try macroDiagnosticsAndLocals(
                    in: body,
                    diagnosticOwnerName: diagnosticOwnerName,
                    diagnosticsBinding: diagnosticsBinding,
                    targetBinding: targetBinding,
                    targetValue: targetValue,
                    graphBinding: graphBinding,
                    context: context,
                    localBindings: locals
                )
                diagnostics.append(contentsOf: bodyResult.diagnostics)
                locals = bodyResult.locals
            case .background(let background):
                let bodyResult = try macroDiagnosticsAndLocals(
                    in: background.body,
                    diagnosticOwnerName: diagnosticOwnerName,
                    diagnosticsBinding: diagnosticsBinding,
                    targetBinding: targetBinding,
                    targetValue: targetValue,
                    graphBinding: graphBinding,
                    context: context,
                    localBindings: locals
                )
                diagnostics.append(contentsOf: bodyResult.diagnostics)
                locals = bodyResult.locals
            case .deferBlock(let deferred):
                let bodyResult = try macroDiagnosticsAndLocals(
                    in: deferred.body,
                    diagnosticOwnerName: diagnosticOwnerName,
                    diagnosticsBinding: diagnosticsBinding,
                    targetBinding: targetBinding,
                    targetValue: targetValue,
                    graphBinding: graphBinding,
                    context: context,
                    localBindings: locals
                )
                diagnostics.append(contentsOf: bodyResult.diagnostics)
                locals = bodyResult.locals
            case .localCallable(let declaration):
                let bodyResult = try macroDiagnosticsAndLocals(
                    in: declaration.body,
                    diagnosticOwnerName: diagnosticOwnerName,
                    diagnosticsBinding: diagnosticsBinding,
                    targetBinding: targetBinding,
                    targetValue: targetValue,
                    graphBinding: graphBinding,
                    context: context,
                    localBindings: locals
                )
                diagnostics.append(contentsOf: bodyResult.diagnostics)
                locals = bodyResult.locals
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    let caseResult = try macroDiagnosticsAndLocals(
                        in: switchCase.body,
                        diagnosticOwnerName: diagnosticOwnerName,
                        diagnosticsBinding: diagnosticsBinding,
                        targetBinding: targetBinding,
                        targetValue: targetValue,
                        graphBinding: graphBinding,
                        context: context,
                        localBindings: locals
                    )
                    diagnostics.append(contentsOf: caseResult.diagnostics)
                    locals = caseResult.locals
                }
                if let defaultBody {
                    let defaultResult = try macroDiagnosticsAndLocals(
                        in: defaultBody,
                        diagnosticOwnerName: diagnosticOwnerName,
                        diagnosticsBinding: diagnosticsBinding,
                        targetBinding: targetBinding,
                        targetValue: targetValue,
                        graphBinding: graphBinding,
                        context: context,
                        localBindings: locals
                    )
                    diagnostics.append(contentsOf: defaultResult.diagnostics)
                    locals = defaultResult.locals
                }
            case .assignment(let target, let expression):
                guard let name = diagnosticMutableBindingName(target) else {
                    continue
                }
                let evaluator = CompileTimeValueEvaluator(
                    targetBinding: targetBinding,
                    targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                    graphBinding: graphBinding,
                    selfValue: macroSelfValue(named: diagnosticOwnerName),
                    localBindings: locals,
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    context: context
                )
                locals[name] =
                    evaluator.evaluate(expression, with: locals)?.expression ?? expression
            case .compoundAssignment(let target, .plusEquals, let expression):
                guard let name = diagnosticMutableBindingName(target),
                    let currentExpression = locals[name]
                else {
                    continue
                }
                let evaluator = CompileTimeValueEvaluator(
                    targetBinding: targetBinding,
                    targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                    graphBinding: graphBinding,
                    selfValue: macroSelfValue(named: diagnosticOwnerName),
                    localBindings: locals,
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    context: context
                )
                switch (
                    evaluator.evaluate(currentExpression, with: locals),
                    evaluator.evaluate(expression, with: locals)
                ) {
                case (.integer(let current)?, .integer(let increment)?):
                    locals[name] = .integer(current + increment)
                case (.string(let current)?, .string(let suffix)?):
                    locals[name] = .string(current + suffix)
                default:
                    continue
                }
            case .expand, .macroInvocation, .return, .break, .continue:
                continue
            }
        }

        return (diagnostics, locals)
    }
    private static func diagnosticMutableBindingName(_ target: AssignmentTarget) -> String? {
        switch target {
        case .local(let name), .state(let name):
            return name
        case .binding, .member:
            return nil
        }
    }

    private static func macroSelfValue(named name: String) -> CompileTimeValue {
        .object(
            typeName: "Macro.Declaration",
            fields: [
                "name": .string(name),
                "identifier": .object(
                    typeName: "Identifier",
                    fields: ["name": .string(name)]
                ),
            ]
        )
    }

    static func macroDiagnostic(
        from expression: Expression,
        diagnosticOwnerName: String,
        diagnosticsBinding: String,
        targetBinding: String,
        targetValue: CompileTimeValue?,
        graphBinding: String?,
        context: MacroExpansionContext,
        localBindings: [String: Expression]
    ) throws -> RangeDiagnostic? {
        guard case .call(let name, let arguments) = expression,
            isMacroDiagnosticsCall(expression, diagnosticsBinding: diagnosticsBinding)
        else {
            return nil
        }

        guard let firstArgument = arguments.first(where: { $0.label == nil })?.value else {
            throw ParseError("Macro @\(diagnosticOwnerName) \(name)(...) requires a message.")
        }

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
            graphBinding: graphBinding,
            selfValue: macroSelfValue(named: diagnosticOwnerName),
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            context: context
        )
        guard case .string(let message) = evaluator.evaluate(firstArgument) else {
            throw ParseError(
                "Macro @\(diagnosticOwnerName) \(name)(...) message must evaluate to String.")
        }

        switch name {
        case "\(diagnosticsBinding).error":
            return RangeDiagnostic(
                severity: .error,
                message: message,
                source: "range-macro",
                code: "macro.diagnostic.error"
            )
        case "\(diagnosticsBinding).warning":
            return RangeDiagnostic(
                severity: .warning,
                message: message,
                source: "range-macro",
                code: "macro.diagnostic.warning"
            )
        case "\(diagnosticsBinding).information", "\(diagnosticsBinding).note":
            return RangeDiagnostic(
                severity: .information,
                message: message,
                source: "range-macro",
                code: "macro.diagnostic.information"
            )
        case "\(diagnosticsBinding).hint":
            return RangeDiagnostic(
                severity: .hint,
                message: message,
                source: "range-macro",
                code: "macro.diagnostic.hint"
            )
        default:
            return nil
        }
    }

    static func isMacroDiagnosticsCall(
        _ expression: Expression,
        diagnosticsBinding: String
    ) -> Bool {
        guard case .call(let name, _) = expression else {
            return false
        }
        return name == "\(diagnosticsBinding).error"
            || name == "\(diagnosticsBinding).warning"
            || name == "\(diagnosticsBinding).information"
            || name == "\(diagnosticsBinding).hint"
            || name == "\(diagnosticsBinding).note"
    }

    static func emittedDeclarationBundle(
        from block: EmittedCodeBlock,
        macro: MacroDeclaration,
        targetValue: CompileTimeValue,
        localBindings: [String: Expression],
        context: MacroExpansionContext
    ) throws -> EmittedDeclarationBundle {
        let rendered = try renderEmittedCodeBlock(
            block,
            macro: macro,
            targetValue: targetValue,
            localBindings: localBindings,
            context: context
        )
        let sourceFile: SourceFileNode
        do {
            var parser = try Parser(source: rendered)
            sourceFile = try parser.parseSourceFile()
        } catch {
            throw ParseError(
                "Could not parse emitted declarations from @\(macro.name).\n\(rendered)")
        }
        return try declarationBundle(from: sourceFile)
    }

    static func renderEmittedCodeBlock(
        _ block: EmittedCodeBlock,
        macro: MacroDeclaration,
        targetValue: CompileTimeValue,
        localBindings: [String: Expression],
        context: MacroExpansionContext
    ) throws -> String {
        guard let bindings = macro.bindings, let target = macro.target else {
            throw ParseError(
                "Macro @\(macro.name) cannot render an attached expansion block without a target.")
        }
        let targetDeclarationName = MacroTargetValueBuilder().declarationName(for: targetValue)
        let targetSurface = MacroTargetSurface(
            targetBinding: bindings.target,
            graphBinding: bindings.graph,
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            targetType: target.typeReference,
            targetDeclarationName: targetDeclarationName,
            localBindings: localBindings,
            targetValue: targetValue,
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
                if expected == .expressionList,
                    let rendered = renderExpressionList(substituted)
                {
                    return rendered
                }
                if let renderedSyntax = targetSurface.renderSyntax(expression) {
                    return renderedSyntax
                }
                return renderExpressionForStringify(substituted)
            case .syntaxMacroInvocation(let name, let arguments):
                guard let syntaxMacro = context.macroDeclarationsByName[name],
                    syntaxMacro.target == nil,
                    let value = try evaluateFreestandingSyntaxMacro(
                        syntaxMacro,
                        arguments: arguments,
                        callerLocals: localBindings,
                        callerTargetBinding: bindings.target,
                        callerTargetValue: targetValue,
                        callerSelfValue: MacroTargetValueBuilder(
                            macroDeclarationsByName: context.macroDeclarationsByName,
                            macroMetadataByName: context.macroMetadataByName,
                            knownObjectTypeNames: context.graphContext.knownObjectTypeNames
                        ).value(for: macro),
                        context: context
                    )
                else {
                    throw ParseError("Unknown syntax macro @\(name).")
                }
                let renderer = MacroSyntaxRenderer(
                    localBindings: localBindings,
                    renderedTargetPath: { targetSurface.renderedTargetPath($0) }
                )
                guard let rendered = renderer.renderSyntax(value) else {
                    throw ParseError("Syntax macro @\(name) did not produce renderable syntax.")
                }
                return rendered
            }
        }.joined(separator: " ")
    }

    static func evaluateFreestandingSyntaxMacro(
        _ macro: MacroDeclaration,
        arguments: [CallArgument],
        callerLocals: [String: Expression],
        callerTargetBinding: String = "__syntax_macro_argument_target__",
        callerTargetValue: CompileTimeValue = .object(
            typeName: "SyntaxMacro.ArgumentTarget",
            fields: [:]
        ),
        callerSelfValue: CompileTimeValue? = nil,
        context: MacroExpansionContext
    ) throws -> CompileTimeValue? {
        guard macro.target == nil,
            let returnType = macro.expansionType
        else {
            return nil
        }

        var bindings = callerLocals
        let argumentBindings = try expressionMacroArgumentBindings(for: macro, arguments: arguments)
        var resolvedArgumentBindings: [String: Expression] = [:]
        for (name, expression) in argumentBindings {
            let resolvedExpression = resolvedSyntaxMacroArgument(
                expression,
                callerLocals: callerLocals,
                callerTargetBinding: callerTargetBinding,
                callerTargetValue: callerTargetValue,
                callerSelfValue: callerSelfValue,
                context: context
            )
            bindings[name] = resolvedExpression
            resolvedArgumentBindings[name] = resolvedExpression
        }

        guard let syntaxBody = macro.syntaxBody else {
            return try evaluateFreestandingSyntaxMacroValueBody(
                macro,
                localBindings: bindings,
                context: context
            )
        }

        noteSyntaxMacroSpliceMemberAccessRisk(syntaxBody, macro: macro, context: context)
        try validateFreestandingSyntaxMacroTemplate(
            syntaxBody,
            macro: macro,
            returnType: returnType
        )
        let rendered = try renderFreestandingSyntaxMacroBody(
            syntaxBody,
            macro: macro,
            localBindings: bindings,
            parameterBindings: resolvedArgumentBindings,
            context: context
        )
        return try syntaxValue(from: rendered, as: returnType)
    }

    static func evaluateFreestandingSyntaxMacroValueBody(
        _ macro: MacroDeclaration,
        localBindings: [String: Expression],
        context: MacroExpansionContext
    ) throws -> CompileTimeValue? {
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: macro.bindings?.target ?? "__syntax_macro_target__",
            targetValue: .object(typeName: "SyntaxMacro.Target", fields: [:]),
            graphBinding: macro.bindings?.graph,
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            context: context
        )

        func evaluateStatements(
            _ statements: [Statement],
            locals initialLocals: [String: Expression]
        ) -> CompileTimeValue? {
            var locals = initialLocals
            for statement in statements {
                switch statement {
                case .localBinding(let declaration):
                    locals[declaration.name] =
                        evaluator.evaluate(declaration.expression, with: locals)?.expression
                        ?? declaration.expression
                case .macroInvocation(let name, let argumentClause, _):
                    guard let invokedMacro = context.macroDeclarationsByName[name] else {
                        return nil
                    }
                    let arguments: [CallArgument]
                    if let argumentClause = argumentClause?.trimmingCharacters(
                        in: .whitespacesAndNewlines),
                        !argumentClause.isEmpty
                    {
                        var parser = try? Parser(source: "macro(\(argumentClause))")
                        guard parser != nil else {
                            return nil
                        }
                        _ = try? parser?.consumeCallableName()
                        guard let parsedArguments = try? parser?.parseInvocationArgumentsIfPresent()
                        else {
                            return nil
                        }
                        arguments = parsedArguments
                    } else {
                        arguments = []
                    }
                    return try? evaluateFreestandingSyntaxMacro(
                        invokedMacro,
                        arguments: arguments,
                        callerLocals: locals,
                        callerSelfValue: MacroTargetValueBuilder(
                            macroDeclarationsByName: context.macroDeclarationsByName,
                            macroMetadataByName: context.macroMetadataByName,
                            knownObjectTypeNames: context.graphContext.knownObjectTypeNames
                        ).value(for: macro),
                        context: context
                    )
                case .return(let expression?):
                    return evaluator.evaluate(expression, with: locals)
                case .expression(let expression):
                    return evaluator.evaluate(expression, with: locals)
                case .switchStatement:
                    return try? statementSyntaxValue(statement)
                case .conditional(let branches):
                    for branch in branches {
                        if let condition = branch.condition {
                            guard case .boolean(true) = evaluator.evaluate(condition, with: locals)
                            else {
                                continue
                            }
                        }
                        return evaluateStatements(branch.body, locals: locals)
                    }
                default:
                    return nil
                }
            }
            return nil
        }

        return evaluateStatements(macro.body, locals: localBindings)
    }

    static func resolvedSyntaxMacroArgument(
        _ expression: Expression,
        callerLocals: [String: Expression],
        callerTargetBinding: String,
        callerTargetValue: CompileTimeValue,
        callerSelfValue: CompileTimeValue? = nil,
        context: MacroExpansionContext
    ) -> Expression {
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: callerTargetBinding,
            targetValue: callerTargetValue,
            selfValue: callerSelfValue,
            localBindings: callerLocals,
            macroDeclarationsByName: context.macroDeclarationsByName,
            context: context
        )
        if let value = evaluator.evaluate(expression),
            let evaluatedExpression = value.expression
        {
            return evaluatedExpression
        }

        guard case .identifier(let name) = expression,
            let callerExpression = callerLocals[name]
        else {
            return expression
        }
        if case .identifier(name) = callerExpression {
            return expression
        }
        return resolvedSyntaxMacroArgument(
            callerExpression,
            callerLocals: callerLocals,
            callerTargetBinding: callerTargetBinding,
            callerTargetValue: callerTargetValue,
            callerSelfValue: callerSelfValue,
            context: context
        )
    }

    static func renderFreestandingSyntaxMacroBody(
        _ block: EmittedCodeBlock,
        macro: MacroDeclaration,
        localBindings: [String: Expression],
        parameterBindings: [String: Expression],
        context: MacroExpansionContext
    ) throws -> String {
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "__syntax_macro_target__",
            targetValue: .object(typeName: "SyntaxMacro.Target", fields: [:]),
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            context: context
        )
        let renderer = MacroSyntaxRenderer(
            localBindings: localBindings,
            renderedTargetPath: { _ in nil }
        )

        return try block.parts.map { part in
            switch part {
            case .text(let text):
                return try renderSyntaxMacroText(text, parameterBindings: parameterBindings)
            case .splice(let expression, let expected):
                guard let value = evaluator.evaluate(expression) else {
                    throw ParseError(
                        "Could not evaluate syntax macro splice: \(renderExpressionForStringify(expression))"
                    )
                }
                if expected == .expressionList,
                    let rendered = renderExpressionList(value, renderer: renderer)
                {
                    return rendered
                }
                if expected == .expression, case .string = value {
                    guard let rendered = value.expression else {
                        return ""
                    }
                    return renderExpressionForStringify(rendered)
                }
                if let renderedSyntax = renderer.renderSyntax(value) {
                    return renderedSyntax
                }
                guard let rendered = value.expression else {
                    return ""
                }
                return renderExpressionForStringify(rendered)
            case .syntaxMacroInvocation(let name, let arguments):
                guard let invokedMacro = context.macroDeclarationsByName[name],
                    invokedMacro.target == nil,
                    let value = try evaluateFreestandingSyntaxMacro(
                        invokedMacro,
                        arguments: arguments,
                        callerLocals: localBindings,
                        callerSelfValue: MacroTargetValueBuilder(
                            macroDeclarationsByName: context.macroDeclarationsByName,
                            macroMetadataByName: context.macroMetadataByName,
                            knownObjectTypeNames: context.graphContext.knownObjectTypeNames
                        ).value(for: macro),
                        context: context
                    ),
                    let rendered = renderer.renderSyntax(value)
                else {
                    throw ParseError("Could not render syntax macro @\(name).")
                }
                return rendered
            }
        }.joined(separator: " ")
    }

    static func noteSyntaxMacroSpliceMemberAccessRisk(
        _ block: EmittedCodeBlock,
        macro: MacroDeclaration,
        context: MacroExpansionContext
    ) {
        // TODO: Emit a compiler warning once the expander has a retained warning
        // channel. Identifier splices in member chains are allowed because the
        // expanded syntax is still type-checked at compile time, but this use is
        // less statically proven at macro-template validation time.
        let parameterTypes = Dictionary(
            uniqueKeysWithValues: macro.parameters.map {
                ($0.localName, $0.typeReference?.displayName ?? "")
            }
        )
        let hasIdentifierMemberSplice = block.parts.enumerated().contains { index, part in
            guard case .splice(let expression, _) = part,
                case .identifier(let name) = expression,
                parameterTypes[name] == "Identifier",
                index + 1 < block.parts.count,
                case .text(let followingText) = block.parts[index + 1],
                syntaxTextStartsWithMemberAccess(followingText)
            else {
                return false
            }
            return true
        }
        guard hasIdentifierMemberSplice else {
            return
        }
        context.diagnosticEngine?.warning(
            "Spliced Identifier is used as a member-access base. This chain is checked after macro expansion.",
            source: "range-macro-expander",
            code: "macro.identifier-member-splice",
            path: context.currentPath
        )
    }

    static func syntaxTextStartsWithMemberAccess(_ text: String) -> Bool {
        do {
            var lexer = Lexer(source: text)
            return try lexer.tokenize().first { $0.token != .eof }?.token == .dot
        } catch {
            return false
        }
    }

    static func renderSyntaxMacroText(
        _ text: String,
        parameterBindings: [String: Expression]
    ) throws -> String {
        var lexer = Lexer(source: text)
        let tokens = try lexer.tokenize().filter { $0.token != .eof }
        return tokens.map { lexedToken in
            switch lexedToken.token {
            case .identifier(let name), .keyword(let name):
                if let expression = parameterBindings[name] {
                    return renderExpressionForStringify(expression)
                }
                return name
            default:
                return renderMacroToken(lexedToken.token)
            }
        }.joined(separator: " ")
    }

    static func renderMacroToken(_ token: Token) -> String {
        switch token {
        case .hash:
            return "#"
        case .identifier(let value):
            return value
        case .foreignBody(_, let value):
            return value
        case .stringLiteral(let value):
            return "\"\(value)\""
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .keyword(let value):
            return value
        case .macroAttribute(let name, let argument):
            if let argument {
                return "@\(name)(\(argument))"
            }
            return "@\(name)"
        case .leftBrace:
            return "{"
        case .rightBrace:
            return "}"
        case .leftParen:
            return "("
        case .rightParen:
            return ")"
        case .leftBracket:
            return "["
        case .rightBracket:
            return "]"
        case .asterisk:
            return "*"
        case .dot:
            return "."
        case .dotDotLess:
            return "..<"
        case .ellipsis:
            return "..."
        case .colon:
            return ":"
        case .arrow:
            return "->"
        case .bang:
            return "!"
        case .equal:
            return "="
        case .equalEqual:
            return "=="
        case .bangEqual:
            return "!="
        case .minus:
            return "-"
        case .less:
            return "<"
        case .lessEqual:
            return "<="
        case .greater:
            return ">"
        case .greaterEqual:
            return ">="
        case .plus:
            return "+"
        case .plusEqual:
            return "+="
        case .slash:
            return "/"
        case .ampersand:
            return "&"
        case .andAnd:
            return "&&"
        case .pipe:
            return "|"
        case .orOr:
            return "||"
        case .question:
            return "?"
        case .questionQuestion:
            return "??"
        case .dollar:
            return "$"
        case .percent:
            return "%"
        case .comma:
            return ","
        case .eof:
            return ""
        }
    }

    static func validateFreestandingSyntaxMacroTemplate(
        _ block: EmittedCodeBlock,
        macro: MacroDeclaration,
        returnType: TypeReference
    ) throws {
        var spliceNames: Set<String> = []
        let source = block.parts.enumerated().map { index, part in
            switch part {
            case .text(let text):
                return text
            case .splice:
                let name = "__splice_\(index)"
                spliceNames.insert(name)
                return name
            case .syntaxMacroInvocation:
                let name = "__syntax_macro_\(index)"
                spliceNames.insert(name)
                return name
            }
        }.joined(separator: " ")
        let allowedIdentifiers = Set(macro.parameters.map(\.localName)).union(spliceNames)

        switch returnType.displayName {
        case "Expression":
            var parser = try Parser(source: source)
            let expression = try parser.parseExpression()
            try parser.consume(.eof)
            try validateSyntaxMacroExpression(
                expression,
                macroName: macro.name,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: []
            )
        case "Statement", "Switch", "If":
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var localBindings: [String: LocalBindingSymbol] = [:]
            let statement = try parser.parseStatement(localBindings: &localBindings)
            try parser.consume(.eof)
            try validateSyntaxMacroStatement(
                statement,
                macroName: macro.name,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: []
            )
        case "Block":
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var parserLocals: [String: LocalBindingSymbol] = [:]
            var validatorLocals: Set<String> = []
            while parser.peek() != .eof {
                let statement = try parser.parseStatement(localBindings: &parserLocals)
                try validateSyntaxMacroStatement(
                    statement,
                    macroName: macro.name,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: validatorLocals
                )
                if case .localBinding(let declaration) = statement {
                    validatorLocals.insert(declaration.name)
                }
            }
        default:
            return
        }
    }

    static func validateSyntaxMacroStatement(
        _ statement: Statement,
        macroName: String,
        allowedIdentifiers: Set<String>,
        localIdentifiers: Set<String>
    ) throws {
        switch statement {
        case .switchStatement(let expression, let cases, let defaultBody):
            try validateSyntaxMacroExpression(
                expression,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
            for switchCase in cases {
                var caseLocals = localIdentifiers
                if case .enumCase(_, let binding?) = switchCase.pattern {
                    caseLocals.insert(binding.name)
                } else if case .expression(let patternExpression) = switchCase.pattern {
                    try validateSyntaxMacroExpression(
                        patternExpression,
                        macroName: macroName,
                        allowedIdentifiers: allowedIdentifiers,
                        localIdentifiers: localIdentifiers
                    )
                }
                try validateSyntaxMacroStatements(
                    switchCase.body,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: caseLocals
                )
            }
            if let defaultBody {
                try validateSyntaxMacroStatements(
                    defaultBody,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
        case .return(let expression):
            if let expression {
                try validateSyntaxMacroExpression(
                    expression,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
        case .assignment(_, let expression), .compoundAssignment(_, _, let expression),
            .expression(let expression):
            try validateSyntaxMacroExpression(
                expression,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .localBinding(let declaration):
            try validateSyntaxMacroExpression(
                declaration.expression,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .forEach(let name, let sequence, let body):
            try validateSyntaxMacroExpression(
                sequence,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
            var loopLocals = localIdentifiers
            loopLocals.insert(name)
            try validateSyntaxMacroStatements(
                body,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: loopLocals
            )
        case .whileLoop(let condition, let body):
            try validateSyntaxMacroExpression(
                condition,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
            try validateSyntaxMacroStatements(
                body,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .conditional(let branches):
            for branch in branches {
                if let condition = branch.condition {
                    try validateSyntaxMacroExpression(
                        condition,
                        macroName: macroName,
                        allowedIdentifiers: allowedIdentifiers,
                        localIdentifiers: localIdentifiers
                    )
                }
                try validateSyntaxMacroStatements(
                    branch.body,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
        case .break, .continue:
            return
        default:
            return
        }
    }

    static func validateSyntaxMacroStatements(
        _ statements: [Statement],
        macroName: String,
        allowedIdentifiers: Set<String>,
        localIdentifiers: Set<String>
    ) throws {
        var scopedLocals = localIdentifiers
        for statement in statements {
            try validateSyntaxMacroStatement(
                statement,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: scopedLocals
            )
            if case .localBinding(let declaration) = statement {
                scopedLocals.insert(declaration.name)
            }
        }
    }

    static func validateSyntaxMacroExpression(
        _ expression: Expression,
        macroName: String,
        allowedIdentifiers: Set<String>,
        localIdentifiers: Set<String>
    ) throws {
        switch expression {
        case .identifier(let name):
            try validateSyntaxMacroIdentifier(
                name,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .call(let name, let arguments):
            if name.contains(".") {
                try validateSyntaxMacroIdentifier(
                    name,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
            for argument in arguments {
                try validateSyntaxMacroExpression(
                    argument.value,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
        case .array(let elements):
            for element in elements {
                try validateSyntaxMacroExpression(
                    element,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
        case .dictionary(let elements):
            for element in elements {
                try validateSyntaxMacroExpression(
                    element.key,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
                try validateSyntaxMacroExpression(
                    element.value,
                    macroName: macroName,
                    allowedIdentifiers: allowedIdentifiers,
                    localIdentifiers: localIdentifiers
                )
            }
        case .ternary(let condition, let trueExpression, let falseExpression):
            try validateSyntaxMacroExpression(
                condition,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
            try validateSyntaxMacroExpression(
                trueExpression,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
            try validateSyntaxMacroExpression(
                falseExpression,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .unary(_, let expression):
            try validateSyntaxMacroExpression(
                expression,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .binary(let lhs, _, let rhs):
            try validateSyntaxMacroExpression(
                lhs,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
            try validateSyntaxMacroExpression(
                rhs,
                macroName: macroName,
                allowedIdentifiers: allowedIdentifiers,
                localIdentifiers: localIdentifiers
            )
        case .interpolatedString(let string):
            for segment in string.segments {
                if case .expression(let expression) = segment {
                    try validateSyntaxMacroExpression(
                        expression,
                        macroName: macroName,
                        allowedIdentifiers: allowedIdentifiers,
                        localIdentifiers: localIdentifiers
                    )
                }
            }
        default:
            return
        }
    }

    static func validateSyntaxMacroIdentifier(
        _ name: String,
        macroName: String,
        allowedIdentifiers: Set<String>,
        localIdentifiers: Set<String>
    ) throws {
        guard !name.hasPrefix(".") else {
            return
        }
        let root = name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
        guard allowedIdentifiers.contains(root) || localIdentifiers.contains(root) else {
            throw ParseError(
                "Syntax macro @\(macroName) references unknown template identifier '\(root)'. Pass it as a macro parameter or splice it explicitly."
            )
        }
    }

    static func syntaxValue(from source: String, as type: TypeReference) throws -> CompileTimeValue
    {
        if case .array(let elementType) = type {
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var localBindings: [String: LocalBindingSymbol] = [:]
            var values: [CompileTimeValue] = []
            while parser.peek() != .eof {
                let elementName = syntaxMacroTypeName(elementType)
                if elementName == "Expression" {
                    values.append(expressionSyntaxValue(try parser.parseExpression()))
                } else {
                    let statement = try parser.parseStatement(localBindings: &localBindings)
                    if elementName == "Switch", case .switchStatement = statement {
                        values.append(try statementSyntaxValue(statement))
                    } else if elementName == "If", case .conditional = statement {
                        values.append(try statementSyntaxValue(statement))
                    } else if elementName == "Statement" {
                        values.append(try statementSyntaxValue(statement))
                    } else {
                        throw ParseError(
                            "Unsupported syntax macro return type \(type.displayName).")
                    }
                }
            }
            return .array(values)
        }

        switch syntaxMacroTypeName(type) {
        case "Expression":
            var parser = try Parser(source: source)
            let expression = try parser.parseExpression()
            try parser.consume(.eof)
            return expressionSyntaxValue(expression)
        case "Statement":
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var localBindings: [String: LocalBindingSymbol] = [:]
            let statement = try parser.parseStatement(localBindings: &localBindings)
            try parser.consume(.eof)
            return try statementSyntaxValue(statement)
        case "Switch":
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var localBindings: [String: LocalBindingSymbol] = [:]
            let statement = try parser.parseStatement(localBindings: &localBindings)
            guard case .switchStatement = statement else {
                throw ParseError("Syntax macro expected Switch output.")
            }
            try parser.consume(.eof)
            return try statementSyntaxValue(statement)
        case "If":
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var localBindings: [String: LocalBindingSymbol] = [:]
            let statement = try parser.parseStatement(localBindings: &localBindings)
            guard case .conditional = statement else {
                throw ParseError("Syntax macro expected If output.")
            }
            try parser.consume(.eof)
            return try statementSyntaxValue(statement)
        case "Block":
            var parser = try Parser(source: source)
            parser.currentSelfAvailable = true
            var localBindings: [String: LocalBindingSymbol] = [:]
            var statements: [Statement] = []
            while parser.peek() != .eof {
                statements.append(try parser.parseStatement(localBindings: &localBindings))
            }
            return .object(
                typeName: "Block",
                fields: ["statements": .array(try statements.map(statementSyntaxValue))]
            )
        default:
            throw ParseError("Unsupported syntax macro return type \(type.displayName).")
        }
    }

    static func syntaxMacroTypeName(_ type: TypeReference) -> String {
        let name = type.displayName
        let surfaceName: String
        if name.hasPrefix("@") || name.hasPrefix("#") {
            surfaceName = String(name.dropFirst())
        } else {
            surfaceName = name
        }

        switch surfaceName {
        case "block":
            return "Block"
        case "expression":
            return "Expression"
        case "if":
            return "If"
        case "statement":
            return "Statement"
        case "switch":
            return "Switch"
        default:
            return surfaceName
        }
    }

    static func statementSyntaxValue(_ statement: Statement) throws -> CompileTimeValue {
        switch statement {
        case .switchStatement(let expression, let cases, nil):
            return .object(
                typeName: "Switch",
                fields: [
                    "expression": expressionSyntaxValue(expression),
                    "cases": .array(try cases.map(switchCaseSyntaxValue)),
                ]
            )
        case .conditional(let branches):
            guard let first = branches.first, let condition = first.condition else {
                throw ParseError("Syntax macro expected If output.")
            }
            var fields: [String: CompileTimeValue] = [
                "condition": expressionSyntaxValue(condition),
                "thenBody": try blockSyntaxValue(first.body),
            ]
            if branches.count == 2, branches[1].condition == nil {
                fields["elseBody"] = try blockSyntaxValue(branches[1].body)
            } else if branches.count > 1 {
                throw ParseError("Unsupported if statement in syntax macro output.")
            }
            return .object(typeName: "If", fields: fields)
        case .return(let expression):
            var fields: [String: CompileTimeValue] = [:]
            if let expression {
                fields["expression"] = expressionSyntaxValue(expression)
            }
            return .object(typeName: "Return", fields: fields)
        case .break:
            return .object(typeName: "Break", fields: [:])
        case .assignment(let target, let expression):
            return .object(
                typeName: "Assignment",
                fields: [
                    "target": .string(renderAssignmentTarget(target)),
                    "expression": expressionSyntaxValue(expression),
                ]
            )
        case .expression(let expression):
            return .object(
                typeName: "ExpressionStatement",
                fields: ["expression": expressionSyntaxValue(expression)]
            )
        default:
            throw ParseError("Unsupported statement in syntax macro output.")
        }
    }

    static func blockSyntaxValue(_ statements: [Statement]) throws -> CompileTimeValue {
        .object(
            typeName: "Block",
            fields: ["statements": .array(try statements.map(statementSyntaxValue))]
        )
    }

    static func switchCaseSyntaxValue(_ switchCase: SwitchCase) throws -> CompileTimeValue {
        .object(
            typeName: "SwitchCase",
            fields: [
                "pattern": .string(renderSwitchCasePattern(switchCase.pattern)),
                "body": try blockSyntaxValue(switchCase.body),
            ]
        )
    }

    static func expressionSyntaxValue(_ expression: Expression) -> CompileTimeValue {
        .string(renderExpressionForStringify(expression))
    }

    static func renderSwitchCasePattern(_ pattern: SwitchCasePattern) -> String {
        switch pattern {
        case .expression(let expression):
            return renderExpressionForStringify(expression)
        case .enumCase(let name, nil):
            return name.hasPrefix(".") ? name : ".\(name)"
        case .enumCase(let name, let binding?):
            let keyword = binding.kind == .mutable ? "var" : "let"
            let caseName = name.hasPrefix(".") ? name : ".\(name)"
            return "\(caseName)(\(keyword) \(binding.name))"
        }
    }

    static func renderAssignmentTarget(_ target: AssignmentTarget) -> String {
        switch target {
        case .state(let name), .binding(let name), .local(let name):
            return name
        case .member(let base, let name):
            return "\(renderAssignmentTarget(base)).\(name)"
        }
    }

    static func emittedSyntaxKind(
        _ actual: Set<EmittedSyntaxKind>,
        isCompatibleWith expected: EmittedSyntaxKind
    ) -> Bool {
        if expected == .expression || expected == .expressionList {
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
        case .expressionList:
            return "expression list"
        case .typeReference:
            return "type reference"
        case .nominalTypeReference:
            return "nominal type reference"
        case .callableName:
            return "function name"
        }
    }

    static func renderExpressionList(
        _ expression: Expression
    ) -> String? {
        guard case .array(let elements) = expression else {
            return renderExpressionForStringify(expression)
        }
        return elements.map(renderExpressionForStringify).joined(separator: ", ")
    }

    static func renderExpressionList(
        _ value: CompileTimeValue,
        renderer: MacroSyntaxRenderer
    ) -> String? {
        guard case .array(let values) = value else {
            return renderer.renderSyntax(value)
        }
        let rendered = values.compactMap { element -> String? in
            if let syntax = renderer.renderSyntax(element) {
                return syntax
            }
            guard let expression = element.expression else {
                return nil
            }
            return renderExpressionForStringify(expression)
        }
        guard rendered.count == values.count else {
            return nil
        }
        return rendered.joined(separator: ", ")
    }

    static func declarationBundle(from sourceFile: SourceFileNode) throws
        -> EmittedDeclarationBundle
    {
        switch sourceFile {
        case .construct(let declaration):
            return EmittedDeclarationBundle(constructs: [declaration])
        case .enumeration(let declaration):
            return EmittedDeclarationBundle(enumerations: [declaration])
        case .extensions(let declarations):
            return EmittedDeclarationBundle(extensions: declarations)
        case .module(let module):
            return EmittedDeclarationBundle(
                states: module.states,
                callables: module.callables,
                constructs: module.constructs,
                enumerations: module.enumerations,
                macros: module.macros,
                extensions: module.extensions
            )
        case .mainBlock:
            throw ParseError("Macros cannot emit @main blocks.")
        case .macro(let declaration):
            return EmittedDeclarationBundle(macros: [declaration])
        }
    }
}
