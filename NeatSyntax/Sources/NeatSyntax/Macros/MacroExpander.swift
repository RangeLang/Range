import Foundation

public enum MacroExpander {
    private static let expansionLock = NSLock()

    public static func expand(files: [ParsedSourceFile]) throws -> [ParsedSourceFile] {
        expansionLock.lock()
        defer { expansionLock.unlock() }

        let registry = collectMacros(from: files)
        let declarationGraph = DeclarationGraph(files: files)
        let protocols = declarationGraph.protocolsByName
        let graphViews = declarationGraph.views
        try validateMacroSyntaxCaptures(
            macros: Array(registry.values),
            syntaxResolver: graphViews.syntaxResolver
        )
        let context = declarationGraph.macroExpansionContext(macrosByName: registry)
        return try files.map { parsedFile in
            ParsedSourceFile(
                path: parsedFile.path,
                sourceFile: try expand(
                    sourceFile: parsedFile.sourceFile,
                    macros: registry,
                    protocols: protocols,
                    parameterMacroSignatures: context.macroRealizationView.parameterMacroSignatures,
                    literalBridges: context.macroRealizationView.realizedLiteralBridges,
                    context: context
                )
            )
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
        case .macro, .enumeration, .protocolDefinition, .extensions:
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
    ) throws
        -> ConstructDeclaration
    {
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
    ) throws
        -> CallableDeclaration
    {
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
    )
        throws
        -> InitializerDeclaration
    {
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
    ) throws
        -> DerivedDeclaration
    {
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
    ) throws
        -> [Statement]
    {
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
    ) throws
        -> [Statement]
    {
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

    static func lowerLiteralExpressionIfPossible(
        _ expression: Expression,
        expectedType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        literalBridges: [RealizedLiteralBridge],
        context: MacroExpansionContext
    ) throws -> Expression {
        guard let literalType = bootstrapLiteralType(for: expression)
        else {
            return expression
        }

        let bridge =
            contextualLiteralBridge(
                for: literalType.displayName,
                expectedType: expectedType,
                literalBridges: literalBridges
            )
            ?? preferredDefaultLiteralBridge(
                for: literalType.displayName,
                literalBridges: literalBridges
            )

        guard let bridge else {
            return expression
        }

        guard
            let rewritten = try executeInitMacroRewrite(
                macroName: "literal",
                initTarget: bridge.initTarget,
                applicationArguments: [
                    CallArgument(
                        label: bridge.initTarget.parameterLabels.first ?? nil, value: expression)
                ],
                macros: macros,
                context: context
            )
        else {
            throw ParseError(
                "Init macro #literal for \(bridge.initTarget.constructName) could not be interpreted through declaration/application rewrite semantics."
            )
        }

        return rewritten
    }

    static func executeInitMacroRewrite(
        macroName: String,
        initTarget: RealizedInitTarget,
        applicationArguments: [CallArgument],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> Expression? {
        guard let macro = macros[macroName], macroTargetKind(for: macro) == .initializer else {
            return nil
        }

        guard let rewriteExpression = try initRewriteExpression(for: macro, context: context) else {
            return nil
        }

        return executeInitRewriteExpression(
            rewriteExpression,
            targetBinding: macro.bindings.target,
            applicationArguments: applicationArguments,
            initTarget: initTarget
        )
    }

    static func initRewriteExpression(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> Expression? {
        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .initApplication
        {
            return rewrite.payload
        }

        return nil
    }

    static func applyInitMacroRewritesIfNeeded(
        callName: String,
        callArguments: [CallArgument],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> Expression? {
        guard
            let target = matchingInitMacroTarget(
                callName: callName,
                callArguments: callArguments,
                targets: context.macroRealizationView.realizedInitMacroTargets
            )
        else {
            return nil
        }

        var currentArguments = callArguments
        var changed = false

        for macroApplication in target.macros {
            guard let macro = macros[macroApplication.name],
                macroTargetKind(for: macro) == .initializer
            else {
                continue
            }

            guard
                let rewritten = try executeInitMacroRewrite(
                    macroName: macroApplication.name,
                    initTarget: target.initTarget,
                    applicationArguments: currentArguments,
                    macros: macros,
                    context: context
                )
            else {
                continue
            }

            changed = true
            if case .call(let rewrittenName, let rewrittenArguments) = rewritten,
                rewrittenName == target.constructName
            {
                currentArguments = rewrittenArguments
                continue
            }

            return rewritten
        }

        guard changed else {
            return nil
        }

        return .call(name: callName, arguments: currentArguments)
    }

    static func matchingInitMacroTarget(
        callName: String,
        callArguments: [CallArgument],
        targets: [RealizedInitMacroTarget]
    ) -> RealizedInitMacroTarget? {
        let matching = targets.filter {
            $0.constructName == callName
                && $0.parameterLabels.elementsEqual(callArguments.map(\.label), by: { $0 == $1 })
        }

        guard !matching.isEmpty else {
            return nil
        }

        if matching.count == 1 {
            return matching[0]
        }

        let coreMatches = matching.filter(\.isCore)
        if coreMatches.count == 1 {
            return coreMatches[0]
        }

        return nil
    }

    static func applyFunctionMacroRewritesIfNeeded(
        callName: String,
        callArguments: [CallArgument],
        context: MacroExpansionContext
    ) throws -> Expression? {
        guard
            let target = matchingFunctionMacroTarget(
                callName: callName,
                callArguments: callArguments,
                targets: context.macroRealizationView.functionMacroSignatures
            )
        else {
            return nil
        }

        for macro in target.functionMacros {
            guard let rewrite = try functionRewriteExpression(for: macro, context: context) else {
                continue
            }

            let targetBinding = macro.bindings.target
            var bindings: [String: Expression] = [
                "\(targetBinding).application.arguments": .array(callArguments.map(\.value))
            ]
            for (index, argument) in callArguments.enumerated() {
                bindings["\(targetBinding).application.arguments[\(index)].expression"] =
                    argument.value
            }

            return substituteMacroBindings(in: rewrite, bindings: bindings)
        }

        return nil
    }

    static func matchingFunctionMacroTarget(
        callName: String,
        callArguments: [CallArgument],
        targets: [FunctionMacroSignature]
    ) -> FunctionMacroSignature? {
        let matching = targets.filter {
            $0.name == callName
                && $0.labels.elementsEqual(callArguments.map(\.label), by: { $0 == $1 })
        }
        if matching.count == 1 {
            return matching[0]
        }

        let byName = targets.filter { $0.name == callName }
        guard byName.count == 1 else {
            return nil
        }
        return byName[0]
    }

    static func functionRewriteExpression(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> Expression? {
        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .functionApplication {
            return rewrite.payload
        }
        return nil
    }

    static func executeInitRewriteExpression(
        _ expression: Expression,
        targetBinding: String,
        applicationArguments: [CallArgument],
        initTarget: RealizedInitTarget
    ) -> Expression? {
        if let directArgument = resolveInitApplicationArgumentReference(
            expression,
            targetBinding: targetBinding,
            applicationArguments: applicationArguments
        ) {
            return directArgument.value
        }

        guard case .call(let name, let arguments) = expression else {
            return nil
        }

        guard name == "\(targetBinding).declaration.expression",
            arguments.count == 1,
            arguments[0].label == "arguments" || arguments[0].label == nil,
            case .array(let values) = arguments[0].value
        else {
            return nil
        }

        guard values.count == initTarget.parameterLabels.count else {
            return nil
        }

        let rewrittenArguments: [CallArgument] = values.enumerated().compactMap { index, value in
            guard
                let argument = resolveInitApplicationArgumentReference(
                    value,
                    targetBinding: targetBinding,
                    applicationArguments: applicationArguments
                )
            else {
                return nil
            }

            return CallArgument(
                label: argument.label ?? initTarget.parameterLabels[index],
                value: argument.value
            )
        }

        guard rewrittenArguments.count == values.count else {
            return nil
        }

        return .call(
            name: initTarget.constructName,
            arguments: rewrittenArguments
        )
    }

    static func resolveInitApplicationArgumentReference(
        _ expression: Expression,
        targetBinding: String,
        applicationArguments: [CallArgument]
    ) -> CallArgument? {
        switch expression {
        case .identifier(let identifier):
            return resolveInitApplicationArgumentIdentifier(
                identifier,
                targetBinding: targetBinding,
                applicationArguments: applicationArguments
            )
        default:
            return nil
        }
    }

    static func resolveInitApplicationArgumentIdentifier(
        _ identifier: String,
        targetBinding: String,
        applicationArguments: [CallArgument]
    ) -> CallArgument? {
        let wholePrefixes = ["\(targetBinding).application.arguments["]
        let expressionPrefix = "\(targetBinding).application.arguments["

        for prefix in wholePrefixes {
            if let index = indexedReference(identifier, prefix: prefix, suffix: "]") {
                guard applicationArguments.indices.contains(index) else {
                    return nil
                }
                return applicationArguments[index]
            }
        }

        if let index = indexedReference(
            identifier,
            prefix: expressionPrefix,
            suffix: "].expression"
        ) {
            guard applicationArguments.indices.contains(index) else {
                return nil
            }
            let argument = applicationArguments[index]
            return CallArgument(label: argument.label, value: argument.value)
        }

        return nil
    }

    static func bootstrapLiteralType(for expression: Expression) -> BootstrapLiteralType? {
        switch expression {
        case .integer:
            return .intLiteral
        case .double:
            return .floatLiteral
        case .string, .interpolatedString:
            return .stringLiteral
        case .boolean:
            return .boolLiteral
        case .nilLiteral:
            return .nilLiteral
        case .block, .macroInvocation, .identifier, .call, .bindingReference, .array,
            .dictionary, .ternary, .unary, .binary:
            return nil
        }
    }

    static func preferredDefaultLiteralBridge(
        for carrierTypeName: String,
        literalBridges: [RealizedLiteralBridge]
    ) -> RealizedLiteralBridge? {
        LiteralBridgeResolver(realizedLiteralBridges: literalBridges)
            .preferredDefaultBridge(for: carrierTypeName)
    }

    static func contextualLiteralBridge(
        for carrierTypeName: String,
        expectedType: TypeReference?,
        literalBridges: [RealizedLiteralBridge]
    ) -> RealizedLiteralBridge? {
        guard let expectedType else {
            return nil
        }

        return LiteralBridgeResolver(realizedLiteralBridges: literalBridges)
            .bridge(expected: expectedType, carrierTypeName: carrierTypeName)
    }

    static func matchingParameterMacroSignature(
        name: String,
        arguments: [CallArgument],
        signatures: [ParameterMacroSignature],
        context: MacroExpansionContext
    ) throws -> ParameterMacroSignature? {
        for signature in signatures {
            guard signature.name == name else {
                continue
            }

            var variadicIndex: Int?
            for entry in signature.parameterMacrosByIndex.sorted(by: { $0.key < $1.key }) {
                if try parameterApplicationRewritePlan(for: entry.value, context: context)?.isVariadic == true {
                    variadicIndex = entry.key
                    break
                }
            }

            guard let variadicIndex else {
                if signature.labels.elementsEqual(arguments.map(\.label), by: { $0 == $1 }) {
                    return signature
                }
                continue
            }

            guard variadicIndex == signature.labels.count - 1 else {
                continue
            }

            guard arguments.count >= variadicIndex else {
                continue
            }

            let fixedLabels = Array(signature.labels.prefix(variadicIndex))
            let fixedArgumentLabels = Array(arguments.prefix(variadicIndex)).map(\.label)
            guard fixedLabels.elementsEqual(fixedArgumentLabels, by: { $0 == $1 }) else {
                continue
            }

            let variadicLabel = signature.labels[variadicIndex]
            if arguments.dropFirst(variadicIndex).allSatisfy({ $0.label == variadicLabel }) {
                return signature
            }
        }

        return nil
    }

    static func validateConstructMacros(
        applications: [MacroApplication],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws {
        for application in applications {
            guard let macro = macros[application.name] else {
                continue
            }
            guard macroTargetKind(for: macro) == .construct else {
                throw ParseError(
                    "Macro #\(application.name) is used on a construct but targets \(macro.target.typeReference.displayName)."
                )
            }
            _ = try resolvedRewriteCalls(for: macro, context: context)
        }
    }

    static func applyAttachedParameterTypeRewrite(
        macro: MacroDeclaration,
        to typeReference: TypeReference,
        context: MacroExpansionContext
    ) throws -> TypeReference {
        let targetBinding = macro.bindings.target
        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .parameterDeclarationType {
            if let rewrittenType = interpretTypeReferenceRewriteExpression(
                rewrite.payload,
                bindings: [
                    "\(targetBinding).declaration.type": typeReference
                ]
            ) {
                return rewrittenType
            }
        }

        return typeReference
    }

    static func applyParameterApplicationRewrite(
        macro: MacroDeclaration,
        arguments: [CallArgument],
        context: MacroExpansionContext
    ) throws -> CallArgument {
        let targetBinding = macro.bindings.target
        let primaryArgument = arguments.first ?? CallArgument(label: nil, value: .array([]))
        guard let plan = try parameterApplicationRewritePlan(for: macro, context: context) else {
            return primaryArgument
        }

        var bindings: [String: Expression] = [
            "\(targetBinding).application.expression": primaryArgument.value,
            "\(targetBinding).application.arguments": .array(arguments.map(\.value)),
        ]
        for (index, argument) in arguments.enumerated() {
            bindings["\(targetBinding).application.arguments[\(index)].expression"] = argument.value
        }
        if bindings["\(targetBinding).application.arguments[0].expression"] == nil {
            bindings["\(targetBinding).application.arguments[0].expression"] = primaryArgument.value
        }

        let substituted = substituteMacroBindings(
            in: plan.payload,
            bindings: bindings
        )

        return CallArgument(
            label: primaryArgument.label,
            value: interpretAttachedParameterArgumentRewriteExpression(substituted)
        )
    }

    static func parameterApplicationRewritePlan(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> ParameterApplicationRewritePlan? {
        let targetBinding = macro.bindings.target
        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .parameterApplicationArguments
            || rewrite.site == .parameterApplicationArgument
        {
            let isVariadic: Bool
            if rewrite.site == .parameterApplicationArguments,
                case .identifier(let identifier) = rewrite.payload,
                identifier == "\(targetBinding).application.arguments"
            {
                isVariadic = true
            } else {
                isVariadic = false
            }

            return ParameterApplicationRewritePlan(payload: rewrite.payload, isVariadic: isVariadic)
        }

        return nil
    }

    static func macroOperationExpressions(in statements: [Statement]) -> [Expression] {
        var expressions: [Expression] = []

        for statement in statements {
            switch statement {
            case .expression(let expression):
                expressions.append(expression)
            case .conditional(let branches):
                for branch in branches {
                    expressions.append(contentsOf: macroOperationExpressions(in: branch.body))
                }
            case .whileLoop(_, let body), .forEach(_, _, let body), .derived(_, _, let body):
                expressions.append(contentsOf: macroOperationExpressions(in: body))
            case .background(let background):
                expressions.append(contentsOf: macroOperationExpressions(in: background.body))
            case .localCallable(let declaration):
                expressions.append(contentsOf: macroOperationExpressions(in: declaration.body))
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    expressions.append(contentsOf: macroOperationExpressions(in: switchCase.body))
                }
                if let defaultBody {
                    expressions.append(contentsOf: macroOperationExpressions(in: defaultBody))
                }
            case .localBinding, .assignment, .compoundAssignment, .return, .macroInvocation,
                .environmentProvision, .break, .continue:
                continue
            }
        }

        return expressions
    }

    static func interpretAttachedParameterArgumentRewriteExpression(
        _ expression: Expression
    ) -> Expression {
        if let blockBody = closureBodyExpression(from: expression) {
            return .block(blockBody)
        }

        return expression
    }

    static func closureBodyExpression(from expression: Expression) -> [Statement]? {
        guard case .call(let name, let arguments) = expression, name == "Closure" else {
            return nil
        }

        if arguments.count == 1,
            arguments[0].label == "body",
            case .block(let body) = arguments[0].value
        {
            return body
        }

        if arguments.count == 1,
            arguments[0].label == nil,
            case .block(let body) = arguments[0].value
        {
            return body
        }

        return nil
    }

    static func rewriteBody(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> [Statement] {
        var rewriteCalls: [[Statement]] = []

        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .targetDirect
        {
            guard case .block(let body) = rewrite.payload else {
                throw ParseError(
                    "Macro #\(macro.name) target.rewrite(...) must receive a block expression for Block-targeted macros."
                )
            }
            rewriteCalls.append(body)
        }

        guard let rewriteBody = rewriteCalls.first else {
            throw ParseError(
                "Macro #\(macro.name) must call \(macro.bindings.target).rewrite(...) with a block expression."
            )
        }

        if rewriteCalls.count > 1 {
            throw ParseError("Macro #\(macro.name) can only rewrite once in this bootstrap pass.")
        }

        return rewriteBody
    }

    static func rewriteExpression(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> Expression {
        var rewriteExpressions: [Expression] = []

        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .targetDirect
        {
            rewriteExpressions.append(rewrite.payload)
        }

        guard let rewriteExpression = rewriteExpressions.first else {
            throw ParseError(
                "Macro #\(macro.name) must call \(macro.bindings.target).rewrite(...) with an expression."
            )
        }

        if rewriteExpressions.count > 1 {
            throw ParseError("Macro #\(macro.name) can only rewrite once in this bootstrap pass.")
        }

        return rewriteExpression
    }

    static func substituteMacroBindings(
        in statements: [Statement],
        bindings: [String: Expression]
    ) -> [Statement] {
        statements.map { substituteMacroBindings(in: $0, bindings: bindings) }
    }

    static func substituteMacroBindings(
        in statement: Statement,
        bindings: [String: Expression]
    ) -> Statement {
        switch statement {
        case .localBinding(let declaration):
            return .localBinding(
                LocalBindingDeclaration(
                    kind: declaration.kind,
                    name: declaration.name,
                    hasExplicitTypeAnnotation: declaration.hasExplicitTypeAnnotation,
                    type: declaration.type,
                    expression: substituteMacroBindings(
                        in: declaration.expression,
                        bindings: bindings
                    )
                )
            )
        case .derived(let name, let typeName, let body):
            return .derived(
                name: name,
                typeName: typeName,
                body: substituteMacroBindings(in: body, bindings: bindings)
            )
        case .background(let background):
            return .background(
                Background(body: substituteMacroBindings(in: background.body, bindings: bindings))
            )
        case .localCallable(let declaration):
            return .localCallable(
                LocalCallableDeclaration(
                    macros: declaration.macros,
                    attribute: declaration.attribute,
                    name: declaration.name,
                    genericParameters: declaration.genericParameters,
                    hasExplicitParameterClause: declaration.hasExplicitParameterClause,
                    parameters: declaration.parameters,
                    returnType: declaration.returnType,
                    body: substituteMacroBindings(in: declaration.body, bindings: bindings)
                )
            )
        case .assignment(let target, let expression):
            return .assignment(
                target: target,
                expression: substituteMacroBindings(in: expression, bindings: bindings)
            )
        case .compoundAssignment(let target, let operatorSymbol, let expression):
            return .compoundAssignment(
                target: target,
                operatorSymbol: operatorSymbol,
                expression: substituteMacroBindings(in: expression, bindings: bindings)
            )
        case .expression(let expression):
            return .expression(substituteMacroBindings(in: expression, bindings: bindings))
        case .forEach(let name, let sequence, let body):
            return .forEach(
                name: name,
                sequence: substituteMacroBindings(in: sequence, bindings: bindings),
                body: substituteMacroBindings(in: body, bindings: bindings)
            )
        case .whileLoop(let condition, let body):
            return .whileLoop(
                condition: substituteMacroBindings(in: condition, bindings: bindings),
                body: substituteMacroBindings(in: body, bindings: bindings)
            )
        case .conditional(let branches):
            return .conditional(
                branches.map { branch in
                    StatementConditionalBranch(
                        condition: branch.condition.map {
                            substituteMacroBindings(in: $0, bindings: bindings)
                        },
                        body: substituteMacroBindings(in: branch.body, bindings: bindings)
                    )
                }
            )
        case .return(let expression):
            return .return(expression.map { substituteMacroBindings(in: $0, bindings: bindings) })
        case .switchStatement(let expression, let cases, let defaultBody):
            return .switchStatement(
                expression: substituteMacroBindings(in: expression, bindings: bindings),
                cases: cases.map { switchCase in
                    SwitchCase(
                        pattern: substituteMacroBindings(in: switchCase.pattern, bindings: bindings),
                        body: substituteMacroBindings(in: switchCase.body, bindings: bindings)
                    )
                },
                defaultBody: defaultBody.map {
                    substituteMacroBindings(in: $0, bindings: bindings)
                }
            )
        case .macroInvocation(let name, let argumentClause, let body):
            return .macroInvocation(
                name: name,
                argumentClause: argumentClause,
                body: substituteMacroBindings(in: body, bindings: bindings)
            )
        case .environmentProvision, .break, .continue:
            return statement
        }
    }

    static func substituteMacroBindings(
        in expression: Expression,
        bindings: [String: Expression]
    ) -> Expression {
        switch expression {
        case .identifier(let name):
            return bindings[name] ?? expression
        case .call(let name, let arguments):
            return .call(
                name: name,
                arguments: arguments.map { argument in
                    CallArgument(
                        label: argument.label,
                        value: substituteMacroBindings(in: argument.value, bindings: bindings)
                    )
                }
            )
        case .macroInvocation(let name, let arguments):
            return .macroInvocation(
                name: name,
                arguments: arguments.map { argument in
                    CallArgument(
                        label: argument.label,
                        value: substituteMacroBindings(in: argument.value, bindings: bindings)
                    )
                }
            )
        case .array(let elements):
            return .array(elements.map { substituteMacroBindings(in: $0, bindings: bindings) })
        case .dictionary(let elements):
            return .dictionary(
                elements.map { element in
                    DictionaryElement(
                        key: substituteMacroBindings(in: element.key, bindings: bindings),
                        value: substituteMacroBindings(in: element.value, bindings: bindings)
                    )
                }
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            return .ternary(
                condition: substituteMacroBindings(in: condition, bindings: bindings),
                trueExpression: substituteMacroBindings(in: trueExpression, bindings: bindings),
                falseExpression: substituteMacroBindings(in: falseExpression, bindings: bindings)
            )
        case .unary(let operatorSymbol, let nested):
            return .unary(
                operatorSymbol: operatorSymbol,
                expression: substituteMacroBindings(in: nested, bindings: bindings)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: substituteMacroBindings(in: lhs, bindings: bindings),
                operatorSymbol: operatorSymbol,
                rhs: substituteMacroBindings(in: rhs, bindings: bindings)
            )
        case .interpolatedString(let string):
            return .interpolatedString(
                InterpolatedString(
                    segments: string.segments.map { segment in
                        switch segment {
                        case .text:
                            return segment
                        case .expression(let nested):
                            return .expression(
                                substituteMacroBindings(in: nested, bindings: bindings))
                        }
                    }
                )
            )
        case .block(let body):
            return .block(substituteMacroBindings(in: body, bindings: bindings))
        case .integer, .double, .string, .boolean, .nilLiteral, .bindingReference:
            return expression
        }
    }

    static func substituteMacroBindings(
        in pattern: SwitchCasePattern,
        bindings: [String: Expression]
    ) -> SwitchCasePattern {
        switch pattern {
        case .expression(let expression):
            return .expression(substituteMacroBindings(in: expression, bindings: bindings))
        case .enumCase:
            return pattern
        }
    }

    static func interpretTypeReferenceRewriteExpression(
        _ expression: Expression,
        bindings: [String: TypeReference]
    ) -> TypeReference? {
        func interpretTypeName(_ expression: Expression) -> String? {
            switch expression {
            case .identifier(let name):
                return name
            case .string(let value):
                return value
            default:
                return nil
            }
        }

        switch expression {
        case .identifier(let name):
            if let bound = bindings[name] {
                return bound
            }
            return .named(name)

        case .call(let name, let arguments):
            if name == "TypeReference.named" || name == "NamedTypeReference",
                arguments.count == 1,
                arguments[0].label == "name" || arguments[0].label == nil,
                let typeName = interpretTypeName(arguments[0].value)
            {
                return .named(typeName)
            }

            if name == "TypeReference.member" || name == "MemberTypeReference",
                let baseArgument = arguments.first(where: { $0.label == "base" }),
                let nameArgument = arguments.first(where: { $0.label == "name" }),
                let base = interpretTypeReferenceRewriteExpression(
                    baseArgument.value,
                    bindings: bindings
                ),
                let memberName = interpretTypeName(nameArgument.value)
            {
                return .member(base: base, name: memberName)
            }

            if name == "TypeReference.generic" || name == "GenericTypeReference",
                let baseArgument = arguments.first(where: { $0.label == "base" }),
                let argumentsArgument = arguments.first(where: { $0.label == "arguments" }),
                let base = interpretTypeReferenceRewriteExpression(
                    baseArgument.value,
                    bindings: bindings
                ),
                case .array(let genericArgumentExpressions) = argumentsArgument.value,
                let genericArguments = genericArgumentExpressions.compactMap({
                    interpretTypeReferenceRewriteExpression($0, bindings: bindings)
                }) as [TypeReference]?,
                genericArguments.count == genericArgumentExpressions.count
            {
                return .generic(base: base, arguments: genericArguments)
            }

            if name == "TypeReference.array" || name == "ArrayTypeReference",
                arguments.count == 1,
                arguments[0].label == "element" || arguments[0].label == nil,
                let element = interpretTypeReferenceRewriteExpression(
                    arguments[0].value,
                    bindings: bindings
                )
            {
                return .array(element)
            }

            if name == "TypeReference.function" || name == "FunctionTypeReference",
                let parametersArgument = arguments.first(where: { $0.label == "parameters" }),
                let returnTypeArgument = arguments.first(where: { $0.label == "returnType" }),
                case .array(let parameterExpressions) = parametersArgument.value,
                let parameters = parameterExpressions.compactMap({
                    interpretTypeReferenceRewriteExpression($0, bindings: bindings)
                }) as [TypeReference]?,
                parameters.count == parameterExpressions.count,
                let returnType = interpretTypeReferenceRewriteExpression(
                    returnTypeArgument.value,
                    bindings: bindings
                )
            {
                return .function(parameters: parameters, returnType: returnType)
            }

            if name == "TypeReference.optional" || name == "OptionalTypeReference",
                arguments.count == 1,
                arguments[0].label == "wrapped" || arguments[0].label == nil,
                let wrapped = interpretTypeReferenceRewriteExpression(
                    arguments[0].value,
                    bindings: bindings
                )
            {
                return .optional(wrapped)
            }

            if name == "TypeReference.variadic" || name == "VariadicTypeReference",
                arguments.count == 1,
                arguments[0].label == "element" || arguments[0].label == nil,
                let element = interpretTypeReferenceRewriteExpression(
                    arguments[0].value,
                    bindings: bindings
                )
            {
                return .variadic(element)
            }

            return nil

        default:
            return nil
        }
    }

    static func resolvedRewriteCalls(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> [ResolvedRewriteCall] {
        let targetBinding = macro.bindings.target
        let targetKind = macroTargetKind(for: macro)
        let operationExpressions = macroOperationExpressions(in: macro.body)
        try context.validateRewriteSites(
            for: macro,
            targetKind: targetKind,
            operationExpressions: operationExpressions
        ) { expression in
            context.resolvedRewriteCall(
                from: expression,
                targetBinding: targetBinding,
                targetKind: targetKind
            ) != nil
        }
        return operationExpressions.compactMap {
            context.resolvedRewriteCall(
                from: $0,
                targetBinding: targetBinding,
                targetKind: targetKind
            )
        }
    }

    static func substituteMacroTargetCalls(
        in statements: [Statement],
        targetBinding: String,
        targetBlock: [Statement]
    ) -> [Statement] {
        statements.flatMap { statement in
            substituteMacroTargetCall(
                in: statement, targetBinding: targetBinding, targetBlock: targetBlock)
        }
    }

    static func substituteMacroTargetCall(
        in statement: Statement,
        targetBinding: String,
        targetBlock: [Statement]
    ) -> [Statement] {
        switch statement {
        case .expression(.call(let name, let arguments))
        where name == targetBinding && arguments.isEmpty:
            return targetBlock
        case .derived(let name, let typeName, let body):
            return [
                .derived(
                    name: name,
                    typeName: typeName,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .background(let background):
            return [
                .background(
                    Background(body: substituteMacroTargetCalls(
                        in: background.body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
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
                        body: substituteMacroTargetCalls(
                            in: declaration.body,
                            targetBinding: targetBinding,
                            targetBlock: targetBlock
                        )
                    )
                )
            ]
        case .forEach(let name, let sequence, let body):
            return [
                .forEach(
                    name: name,
                    sequence: sequence,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: condition,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .conditional(let branches):
            return [
                .conditional(
                    branches.map { branch in
                        StatementConditionalBranch(
                            condition: branch.condition,
                            body: substituteMacroTargetCalls(
                                in: branch.body,
                                targetBinding: targetBinding,
                                targetBlock: targetBlock
                            )
                        )
                    }
                )
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: expression,
                    cases: cases.map { switchCase in
                        SwitchCase(
                            pattern: switchCase.pattern,
                            body: substituteMacroTargetCalls(
                                in: switchCase.body,
                                targetBinding: targetBinding,
                                targetBlock: targetBlock
                            )
                        )
                    },
                    defaultBody: defaultBody.map {
                        substituteMacroTargetCalls(
                            in: $0,
                            targetBinding: targetBinding,
                            targetBlock: targetBlock
                        )
                    }
                )
            ]
        default:
            return [statement]
        }
    }
}
