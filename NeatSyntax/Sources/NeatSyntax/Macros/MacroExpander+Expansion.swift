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
                                context: context
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
                            context: context
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
                    context: context
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
                    context: context
                )
            },
            callables: try construct.callables.map {
                try expand(
                    callable: $0,
                    macros: macros,
                    protocols: protocols,
                    parameterMacroSignatures: parameterMacroSignatures,
                    literalBridges: literalBridges,
                    context: context
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
        context: MacroExpansionContext
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
                    context: context
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
        context: MacroExpansionContext
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
                    context: context
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
        context: MacroExpansionContext
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
                    context: context
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
            storage = .stored(
                try expand(
                    expression: expression,
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

    static func expand(
        statements: [Statement],
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        parameterMacroSignatures: [ParameterMacroSignature],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext
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
                    context: context
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
        context: MacroExpansionContext
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
                context: context
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
                context: context
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
                        context: context
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
                            context: context
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
                        context: context
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
                        context: context
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
                                context: context
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
            return [
                .assignment(
                    target: target,
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
        case .compoundAssignment(let target, let operatorSymbol, let expression):
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
                                context: context
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
                            context: context
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
