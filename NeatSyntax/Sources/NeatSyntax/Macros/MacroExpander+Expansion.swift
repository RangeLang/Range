extension MacroExpander {
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
            let moduleStateEffects = try stateMacroEffects(
                for: module.states,
                macros: macros
            )
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
                    },
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
                    },
                    constructs: try module.constructs.map {
                        try expand(
                            construct: $0,
                            macros: macros,
                            protocols: protocols,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context
                        )
                    },
                    namespaces: module.namespaces,
                    enumerations: module.enumerations,
                    protocols: module.protocols,
                    macros: module.macros,
                    precedenceGroups: module.precedenceGroups,
                    operators: module.operators,
                    extensions: module.extensions
                )
            )
        case .construct(let declaration):
            return .construct(
                try expand(
                    construct: declaration,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
                ))
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

        let constructStateEffects = try stateMacroEffects(
            for: construct.states,
            macros: macros
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
                    context: context
                )
            },
            environments: construct.environments,
            bindings: construct.bindings,
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
            values: construct.values,
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
        stateEffects: [String: StateMacroEffects] = [:]
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
        stateEffects: [String: StateMacroEffects] = [:]
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
        stateEffects: [String: StateMacroEffects] = [:]
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
        context: MacroExpansionContext
    ) throws -> StateDeclaration {
        let storage: StateStorage

        switch state.storage {
        case .stored(let expression):
            let rewrittenExpression = try applyStateInitializerTransforms(
                to: expression,
                state: state,
                macros: macros
            )
            storage = .stored(
                try expand(
                    expression: rewrittenExpression,
                    expectedType: state.type,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
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

    static func stateMacroEffects(
        for states: [StateDeclaration],
        macros: [String: MacroDeclaration]
    ) throws -> [String: StateMacroEffects] {
        Dictionary(
            uniqueKeysWithValues: try states.map { state in
                (
                    state.name,
                    try stateMacroEffects(for: state, macros: macros)
                )
            }
        )
    }

    static func stateMacroEffects(
        for state: StateDeclaration,
        macros: [String: MacroDeclaration]
    ) throws -> StateMacroEffects {
        var initializerTransforms: [Expression] = []
        var setterTransforms: [Expression] = []

        for application in state.macros {
            guard let macro = macros[application.name] else {
                throw ParseError("Unknown attached macro @\(application.name).")
            }
            guard macroTargetKind(for: macro) == .state else {
                throw ParseError(
                    "Macro #\(application.name) is used on a state but targets \(macro.target.typeReference.displayName)."
                )
            }

            let argumentBindings = try parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )

            for registration in try stateTransformRegistrations(for: macro) {
                let substituted = substituteMacroBindings(
                    in: registration.body,
                    bindings: argumentBindings
                )

                switch registration.hook {
                case .initializer:
                    initializerTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [registration.parameterName: .identifier("__state_input__")]
                        )
                    )
                case .setter:
                    setterTransforms.append(
                        substituteMacroBindings(
                            in: substituted,
                            bindings: [registration.parameterName: .identifier("__state_input__")]
                        )
                    )
                case .getter:
                    continue
                }
            }
        }

        return StateMacroEffects(
            type: state.type,
            initializerTransforms: initializerTransforms,
            setterTransforms: setterTransforms
        )
    }

    static func applyStateInitializerTransforms(
        to expression: Expression,
        state: StateDeclaration,
        macros: [String: MacroDeclaration]
    ) throws -> Expression {
        let effects = try stateMacroEffects(for: state, macros: macros)
        return applyStateTransforms(
            effects.initializerTransforms,
            to: expression
        )
    }

    static func applyStateTransforms(
        _ transforms: [Expression],
        to expression: Expression
    ) -> Expression {
        transforms.reduce(expression) { current, transform in
            substituteMacroBindings(
                in: transform,
                bindings: ["__state_input__": current]
            )
        }
    }

    static func expectedType(
        for target: AssignmentTarget,
        stateEffects: [String: StateMacroEffects]
    ) -> TypeReference? {
        switch target {
        case .state(let name):
            return stateEffects[name]?.type
        case .member(let base, _):
            return expectedType(for: base, stateEffects: stateEffects)
        case .binding, .environment, .local:
            return nil
        }
    }

    static func rewrittenStateAssignmentExpression(
        target: AssignmentTarget,
        expression: Expression,
        stateEffects: [String: StateMacroEffects]
    ) -> Expression {
        guard case .state(let name) = target,
            let effects = stateEffects[name],
            !effects.setterTransforms.isEmpty
        else {
            return expression
        }

        return applyStateTransforms(effects.setterTransforms, to: expression)
    }

    static func rewrittenCompoundStateAssignment(
        target: AssignmentTarget,
        operatorSymbol: CompoundOperator,
        expression: Expression,
        stateEffects: [String: StateMacroEffects]
    ) -> Statement? {
        guard case .state(let name) = target,
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
            expression: applyStateTransforms(effects.setterTransforms, to: combinedExpression)
        )
    }

    static func expand(
        statements: [Statement],
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext,
        stateEffects: [String: StateMacroEffects] = [:]
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
        stateEffects: [String: StateMacroEffects] = [:]
    ) throws -> [Statement] {
        switch statement {
        case .macroInvocation(let name, let argumentClause, let body):
            guard let macro = macros[name] else {
                throw ParseError("Unknown block-targeted macro #\(name).")
            }
            guard macroTargetKind(for: macro) == .block
            else {
                throw ParseError("Macro #\(name) does not target Block.")
            }
            let expandedTarget = try expand(
                statements: body,
                macros: macros,
                protocols: protocols,
                parameterMacroSignatures: parameterMacroSignatures,
                literalBridges: literalBridges,
                context: context,
                stateEffects: stateEffects
            )
            let argumentBindings = try parseMacroArgumentBindings(
                for: macro,
                argumentClause: argumentClause
            )
            let rewriteBody = try rewriteBody(for: macro, context: context)
            let bindingSubstituted = substituteMacroBindings(
                in: rewriteBody,
                bindings: argumentBindings
            )
            let targetSubstituted = substituteMacroTargetCalls(
                in: bindingSubstituted,
                targetBinding: macro.bindings.target,
                targetBlock: expandedTarget
            )
            return try expand(
                statements: targetSubstituted,
                macros: macros,
                protocols: protocols,
                parameterMacroSignatures: parameterMacroSignatures,
                literalBridges: literalBridges,
                context: context,
                stateEffects: stateEffects
            )
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
                        context: context
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
                        context: context
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
                                    context: context)
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
                            context: context
                        )
                    )
                )
            ]
        case .assignment(let target, let expression):
            let rewrittenExpression = rewrittenStateAssignmentExpression(
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
                        context: context
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
                        context: context
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
                            context: context)
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
                        context: context
                    ),
                    cases: try cases.map { switchCase in
                        SwitchCase(
                            pattern: try expand(
                                switchCasePattern: switchCase.pattern,
                                macros: macros,
                                parameterMacroSignatures: parameterMacroSignatures,
                                literalBridges: literalBridges,
                                context: context
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
        context: MacroExpansionContext
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
                    context: context
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
        context: MacroExpansionContext
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
                        context: context
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
                            context: context
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
                context: context
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
                        context: context
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
                            context: context
                        ),
                        value: try expand(
                            expression: element.value,
                            expectedType: nil,
                            macros: macros,
                            parameterMacroSignatures: parameterMacroSignatures,
                            literalBridges: literalBridges,
                            context: context
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
                    context: context),
                trueExpression: try expand(
                    expression: trueExpression,
                    expectedType: expectedType,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
                ),
                falseExpression: try expand(
                    expression: falseExpression,
                    expectedType: expectedType,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
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
                    context: context)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: try expand(
                    expression: lhs,
                    expectedType: nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context),
                operatorSymbol: operatorSymbol,
                rhs: try expand(
                    expression: rhs,
                    expectedType: nil,
                    macros: macros,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context)
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
                                    context: context
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
                        context: context
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
        case .identifier, .bindingReference:
            return expression
        }
    }
}
