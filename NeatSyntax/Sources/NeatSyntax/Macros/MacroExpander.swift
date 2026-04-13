import Foundation

public enum MacroExpander {
    nonisolated(unsafe) private static var activeInitMacroTargets: [RealizedInitMacroTarget] = []
    nonisolated(unsafe) private static var activeFunctionMacroTargets:
        [AttachedFunctionMacroSignature] =
            []
    nonisolated(unsafe) private static var activeSyntaxResolver: DeclarationSyntaxResolver?
    nonisolated(unsafe) private static var activeConstructsByName: [String: ConstructDeclaration] =
        [:]

    public static func expand(files: [ParsedSourceFile]) throws -> [ParsedSourceFile] {
        let registry = collectMacros(from: files)
        let declarationGraph = DeclarationGraph(files: files)
        let protocols = declarationGraph.protocolsByName
        try validateMacroSyntaxCaptures(
            macros: Array(registry.values),
            syntaxResolver: declarationGraph.syntaxResolver
        )
        let attachedParameterCallables = collectAttachedParameterCallables(
            from: files,
            macros: registry
        )
        let attachedFunctionCallables = collectAttachedFunctionCallables(
            from: files,
            macros: registry
        )
        let attachedLiteralConstructs = declarationGraph.realizedLiteralBridges
        activeInitMacroTargets = declarationGraph.realizedInitMacroTargets
        activeFunctionMacroTargets = attachedFunctionCallables
        activeSyntaxResolver = declarationGraph.syntaxResolver
        activeConstructsByName = declarationGraph.constructsByName
        defer {
            activeInitMacroTargets = []
            activeFunctionMacroTargets = []
            activeSyntaxResolver = nil
            activeConstructsByName = [:]
        }
        return try files.map { parsedFile in
            ParsedSourceFile(
                path: parsedFile.path,
                sourceFile: try expand(
                    sourceFile: parsedFile.sourceFile,
                    macros: registry,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            )
        }
    }

    static func expand(
        sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
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
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
                            ))
                    },
                    states: try module.states.map {
                        try expand(
                            state: $0,
                            macros: macros,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        )
                    },
                    callables: try module.callables.map {
                        try expand(
                            callable: $0,
                            macros: macros,
                            protocols: protocols,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        )
                    },
                    constructs: try module.constructs.map {
                        try expand(
                            construct: $0,
                            macros: macros,
                            protocols: protocols,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
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
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                ))
        case .macro, .enumeration, .protocolDefinition, .extensions:
            return sourceFile
        }
    }

    static func expand(
        construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) throws
        -> ConstructDeclaration
    {
        try validateAttachedConstructMacros(
            applications: construct.macros,
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
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            },
            environments: construct.environments,
            bindings: construct.bindings,
            deriveds: try construct.deriveds.map {
                try expand(
                    derived: $0,
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            },
            values: construct.values,
            initializers: try carriedInitializers.map {
                try expand(
                    initializer: $0,
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            },
            callables: try construct.callables.map {
                try expand(
                    callable: $0,
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            },
            constructs: try construct.constructs.map {
                try expand(
                    construct: $0,
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            }
        )
    }

    static func expand(
        callable: CallableDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
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
            parameters: try expand(parameters: callable.parameters, macros: macros),
            returnType: callable.returnType,
            body: try callable.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: callable.returnType,
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            }
        )
    }

    static func expand(
        initializer: InitializerDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
    )
        throws
        -> InitializerDeclaration
    {
        InitializerDeclaration(
            macros: initializer.macros,
            parameters: try expand(parameters: initializer.parameters, macros: macros),
            body: try initializer.body.map {
                try expand(
                    statements: $0,
                    expectedReturnType: nil,
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            }
        )
    }

    static func expand(
        derived: DerivedDeclaration,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
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
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            }
        )
    }

    static func expand(
        state: StateDeclaration,
        macros: [String: MacroDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) throws -> StateDeclaration {
        let storage: StateStorage

        switch state.storage {
        case .stored(let expression):
            storage = .stored(
                try expand(
                    expression: expression,
                    expectedType: state.type,
                    macros: macros,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
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
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
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
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                ))
        }
        return expanded
    }

    static func expand(
        statement: Statement,
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        protocols: [String: ProtocolDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) throws
        -> [Statement]
    {
        switch statement {
        case .freestandingMacro(let name, let argumentClause, let body):
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
                attachedParameterCallables: attachedParameterCallables,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
            let argumentBindings = try parseMacroArgumentBindings(
                for: macro,
                argumentClause: argumentClause
            )
            let rewriteBody = try rewriteBody(for: macro)
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
                attachedParameterCallables: attachedParameterCallables,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        case .background(let body):
            return [
                .background(
                    body: try expand(
                        statements: body,
                        expectedReturnType: nil,
                        macros: macros,
                        protocols: protocols,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )
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
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ),
                    body: try expand(
                        statements: body,
                        expectedReturnType: expectedReturnType,
                        macros: macros,
                        protocols: protocols,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ))
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: try expand(
                        expression: condition,
                        expectedType: .named("Bool"),
                        macros: macros,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ),
                    body: try expand(
                        statements: body,
                        expectedReturnType: expectedReturnType,
                        macros: macros,
                        protocols: protocols,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
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
                                    attachedParameterCallables: attachedParameterCallables,
                                    attachedLiteralConstructs: attachedLiteralConstructs)
                            },
                            body: try expand(
                                statements: branch.body,
                                expectedReturnType: expectedReturnType,
                                macros: macros,
                                protocols: protocols,
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
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
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs))
            ]
        case .return(let expression):
            return [
                .return(
                    try expression.map {
                        try expand(
                            expression: $0,
                            expectedType: expectedReturnType,
                            macros: macros,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs)
                    })
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: try expand(
                        expression: expression,
                        expectedType: nil,
                        macros: macros,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ),
                    cases: try cases.map { switchCase in
                        SwitchCase(
                            value: try expand(
                                expression: switchCase.value,
                                expectedType: nil,
                                macros: macros,
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
                            ),
                            body: try expand(
                                statements: switchCase.body,
                                expectedReturnType: expectedReturnType,
                                macros: macros,
                                protocols: protocols,
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
                            )
                        )
                    },
                    defaultBody: try defaultBody.map {
                        try expand(
                            statements: $0,
                            expectedReturnType: expectedReturnType,
                            macros: macros,
                            protocols: protocols,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        )
                    }
                )
            ]
        default:
            return [statement]
        }
    }

    static func expand(
        parameters: [NeatFunctionParameter],
        macros: [String: MacroDeclaration]
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
                try applyAttachedParameterTypeRewrite(macro: macro, to: currentType)
            }

            return NeatFunctionParameter(
                macros: parameter.macros,
                localName: parameter.localName,
                externalLabel: parameter.externalLabel,
                typeReference: rewrittenType,
                slotName: parameter.slotName,
                capturesSyntax: parameter.capturesSyntax
            )
        }
    }

    static func expand(
        expression: Expression,
        expectedType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
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
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )
                )
            }

            let callArguments: [CallArgument]
            if let signature = try matchingAttachedParameterCallable(
                name: name,
                arguments: rewrittenArguments,
                signatures: attachedParameterCallables
            ) {
                var wrappedArguments: [CallArgument] = []
                var argumentIndex = 0

                for parameterIndex in signature.labels.indices {
                    if let macro = signature.attachedParameterMacrosByIndex[parameterIndex],
                        try parameterApplicationRewritePlan(for: macro)?.isVariadic == true
                    {
                        let consumedArguments = Array(rewrittenArguments.dropFirst(argumentIndex))
                        wrappedArguments.append(
                            try applyParameterApplicationRewrite(
                                macro: macro,
                                arguments: consumedArguments
                            )
                        )
                        argumentIndex = rewrittenArguments.count
                        continue
                    }

                    guard argumentIndex < rewrittenArguments.count else {
                        break
                    }

                    let argument = rewrittenArguments[argumentIndex]
                    if let macro = signature.attachedParameterMacrosByIndex[parameterIndex] {
                        wrappedArguments.append(
                            try applyParameterApplicationRewrite(
                                macro: macro,
                                arguments: [argument]
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
                macros: macros
            ) {
                return rewrittenByInitMacro
            }

            if let rewrittenByFunctionMacro = try applyFunctionMacroRewritesIfNeeded(
                callName: name,
                callArguments: callArguments
            ) {
                return rewrittenByFunctionMacro
            }

            return .call(name: name, arguments: callArguments)
        case .freestandingMacro(let name, let arguments):
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
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        )
                    )
                }
                return .freestandingMacro(name: name, arguments: rewrittenArguments)
            }

            let argumentBindings = try expressionMacroArgumentBindings(
                for: macro,
                arguments: arguments
            )
            let rewrite = try rewriteExpression(for: macro)
            let interpreted = interpretExpressionMacroRewrite(rewrite, bindings: argumentBindings)
            let substituted = substituteMacroBindings(in: interpreted, bindings: argumentBindings)
            return try expand(
                expression: substituted,
                expectedType: expectedType,
                macros: macros,
                attachedParameterCallables: attachedParameterCallables,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        case .array(let elements):
            return .array(
                try elements.map {
                    try expand(
                        expression: $0,
                        expectedType: nil,
                        macros: macros,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
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
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        ),
                        value: try expand(
                            expression: element.value,
                            expectedType: nil,
                            macros: macros,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
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
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs),
                trueExpression: try expand(
                    expression: trueExpression,
                    expectedType: expectedType,
                    macros: macros,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                ),
                falseExpression: try expand(
                    expression: falseExpression,
                    expectedType: expectedType,
                    macros: macros,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            )
        case .unary(let operatorSymbol, let nested):
            return .unary(
                operatorSymbol: operatorSymbol,
                expression: try expand(
                    expression: nested,
                    expectedType: operatorSymbol == .not ? .named("Bool") : nil,
                    macros: macros,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: try expand(
                    expression: lhs,
                    expectedType: nil,
                    macros: macros,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs),
                operatorSymbol: operatorSymbol,
                rhs: try expand(
                    expression: rhs,
                    expectedType: nil,
                    macros: macros,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs)
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
                                    attachedParameterCallables: attachedParameterCallables,
                                    attachedLiteralConstructs: attachedLiteralConstructs
                                ))
                        }
                    }
                )
            )
            return try lowerLiteralExpressionIfPossible(
                expanded,
                expectedType: expectedType,
                macros: macros,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        case .block(let body):
            return .block(
                try body.flatMap {
                    try expand(
                        statement: $0,
                        expectedReturnType: nil,
                        macros: macros,
                        protocols: [:],
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )
                }
            )
        case .integer, .double, .string, .boolean, .nilLiteral:
            return try lowerLiteralExpressionIfPossible(
                expression,
                expectedType: expectedType,
                macros: macros,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        case .identifier, .bindingReference:
            return expression
        }
    }

    static func lowerLiteralExpressionIfPossible(
        _ expression: Expression,
        expectedType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) throws -> Expression {
        guard let literalType = bootstrapLiteralType(for: expression)
        else {
            return expression
        }

        let bridge =
            contextualLiteralBridge(
                for: literalType.displayName,
                expectedType: expectedType,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
            ?? preferredDefaultLiteralBridge(
                for: literalType.displayName,
                attachedLiteralConstructs: attachedLiteralConstructs
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
                macros: macros
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
        macros: [String: MacroDeclaration]
    ) throws -> Expression? {
        guard let macro = macros[macroName], macroTargetKind(for: macro) == .initializer else {
            return nil
        }

        guard let rewriteExpression = try initRewriteExpression(for: macro) else {
            return nil
        }

        return executeInitRewriteExpression(
            rewriteExpression,
            targetBinding: macro.bindings.target,
            applicationArguments: applicationArguments,
            initTarget: initTarget
        )
    }

    static func initRewriteExpression(for macro: MacroDeclaration) throws -> Expression? {
        for rewrite in try resolvedRewriteCalls(for: macro) where rewrite.site == .initApplication {
            return rewrite.payload
        }

        return nil
    }

    static func applyInitMacroRewritesIfNeeded(
        callName: String,
        callArguments: [CallArgument],
        macros: [String: MacroDeclaration]
    ) throws -> Expression? {
        guard
            let target = matchingInitMacroTarget(
                callName: callName,
                callArguments: callArguments,
                targets: activeInitMacroTargets
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
                    macros: macros
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
        callArguments: [CallArgument]
    ) throws -> Expression? {
        guard
            let target = matchingFunctionMacroTarget(
                callName: callName,
                callArguments: callArguments,
                targets: activeFunctionMacroTargets
            )
        else {
            return nil
        }

        for macro in target.attachedFunctionMacros {
            guard let rewrite = try functionRewriteExpression(for: macro) else {
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
        targets: [AttachedFunctionMacroSignature]
    ) -> AttachedFunctionMacroSignature? {
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

    static func functionRewriteExpression(for macro: MacroDeclaration) throws -> Expression? {
        for rewrite in try resolvedRewriteCalls(for: macro)
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

    static func indexedReference(
        _ identifier: String,
        prefix: String,
        suffix: String
    ) -> Int? {
        guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else {
            return nil
        }
        let start = identifier.index(identifier.startIndex, offsetBy: prefix.count)
        let end = identifier.index(identifier.endIndex, offsetBy: -suffix.count)
        guard start <= end else {
            return nil
        }
        return Int(identifier[start..<end])
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
        case .block, .freestandingMacro, .identifier, .call, .bindingReference, .array,
            .dictionary, .ternary, .unary, .binary:
            return nil
        }
    }

    static func preferredDefaultLiteralBridge(
        for carrierTypeName: String,
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) -> RealizedLiteralBridge? {
        LiteralBridgeResolver(realizedLiteralBridges: attachedLiteralConstructs)
            .preferredDefaultBridge(for: carrierTypeName)
    }

    static func contextualLiteralBridge(
        for carrierTypeName: String,
        expectedType: TypeReference?,
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) -> RealizedLiteralBridge? {
        guard let expectedType else {
            return nil
        }

        return LiteralBridgeResolver(realizedLiteralBridges: attachedLiteralConstructs)
            .bridge(expected: expectedType, carrierTypeName: carrierTypeName)
    }

    static func matchingAttachedParameterCallable(
        name: String,
        arguments: [CallArgument],
        signatures: [AttachedParameterMacroSignature]
    ) throws -> AttachedParameterMacroSignature? {
        for signature in signatures {
            guard signature.name == name else {
                continue
            }

            var variadicIndex: Int?
            for entry in signature.attachedParameterMacrosByIndex.sorted(by: { $0.key < $1.key }) {
                if try parameterApplicationRewritePlan(for: entry.value)?.isVariadic == true {
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

    static func validateAttachedConstructMacros(
        applications: [MacroApplication],
        macros: [String: MacroDeclaration]
    ) throws {
        for application in applications {
            guard let macro = macros[application.name] else {
                continue
            }
            guard macroTargetKind(for: macro) == .construct else {
                throw ParseError(
                    "Macro #\(application.name) is attached to a construct but targets \(macro.target.typeReference.displayName)."
                )
            }
            _ = try resolvedRewriteCalls(for: macro)
        }
    }

    static func applyAttachedParameterTypeRewrite(
        macro: MacroDeclaration,
        to typeReference: TypeReference
    ) throws -> TypeReference {
        let targetBinding = macro.bindings.target
        for rewrite in try resolvedRewriteCalls(for: macro)
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
        arguments: [CallArgument]
    ) throws -> CallArgument {
        let targetBinding = macro.bindings.target
        let primaryArgument = arguments.first ?? CallArgument(label: nil, value: .array([]))
        guard let plan = try parameterApplicationRewritePlan(for: macro) else {
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
        for macro: MacroDeclaration
    ) throws -> ParameterApplicationRewritePlan? {
        let targetBinding = macro.bindings.target
        for rewrite in try resolvedRewriteCalls(for: macro)
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
            case .whileLoop(_, let body), .forEach(_, _, let body), .derived(_, _, let body),
                .background(let body):
                expressions.append(contentsOf: macroOperationExpressions(in: body))
            case .localCallable(let declaration):
                expressions.append(contentsOf: macroOperationExpressions(in: declaration.body))
            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    expressions.append(contentsOf: macroOperationExpressions(in: switchCase.body))
                }
                if let defaultBody {
                    expressions.append(contentsOf: macroOperationExpressions(in: defaultBody))
                }
            case .localBinding, .assignment, .compoundAssignment, .return, .freestandingMacro,
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

    static func rewriteBody(for macro: MacroDeclaration) throws -> [Statement] {
        var rewriteCalls: [[Statement]] = []

        for rewrite in try resolvedRewriteCalls(for: macro) where rewrite.site == .targetDirect {
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

    static func rewriteExpression(for macro: MacroDeclaration) throws -> Expression {
        var rewriteExpressions: [Expression] = []

        for rewrite in try resolvedRewriteCalls(for: macro) where rewrite.site == .targetDirect {
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
        case .background(let body):
            return .background(
                body: substituteMacroBindings(in: body, bindings: bindings)
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
                        value: substituteMacroBindings(in: switchCase.value, bindings: bindings),
                        body: substituteMacroBindings(in: switchCase.body, bindings: bindings)
                    )
                },
                defaultBody: defaultBody.map {
                    substituteMacroBindings(in: $0, bindings: bindings)
                }
            )
        case .freestandingMacro(let name, let argumentClause, let body):
            return .freestandingMacro(
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
        case .freestandingMacro(let name, let arguments):
            return .freestandingMacro(
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

    static func macroTargetKind(for macro: MacroDeclaration) -> MacroTargetKind {
        macroTargetKind(for: macro.target.typeReference)
    }

    static func macroTargetKind(for typeReference: TypeReference) -> MacroTargetKind {
        let name: String
        switch typeReference {
        case .named(let named):
            name = named
        case .member(_, let member):
            name = member
        case .generic(let base, _):
            return macroTargetKind(for: base)
        case .array, .function, .optional, .variadic:
            name = typeReference.displayName
        }

        switch name {
        case "Expression":
            return .expression
        case "Block":
            return .block
        case "Parameter":
            return .parameter
        case "Init":
            return .initializer
        case "Function":
            return .function
        case "Construct":
            return .construct
        default:
            return .other(name)
        }
    }

    static func resolvedRewriteCalls(for macro: MacroDeclaration) throws -> [ResolvedRewriteCall] {
        let targetBinding = macro.bindings.target
        let targetKind = macroTargetKind(for: macro)
        try validateRewriteSites(for: macro, targetKind: targetKind)
        return macroOperationExpressions(in: macro.body).compactMap {
            resolvedRewriteCall(
                from: $0,
                targetBinding: targetBinding,
                targetKind: targetKind
            )
        }
    }

    static func allowedRewritePaths(
        targetBinding: String,
        targetType: TypeReference
    ) -> Set<String> {
        guard
            let syntaxResolver = activeSyntaxResolver,
            let targetName = syntaxResolver.nominalName(of: targetType)
        else {
            return []
        }

        var paths: Set<String> = []

        func supportsRewrite(_ typeName: String) -> Bool {
            syntaxResolver.declaration(named: typeName, conformsTo: "SupportsRewrite")
        }

        func resolvedValueType(
            named rawTypeName: String,
            ownerTypeName: String
        ) -> (typeName: String, isArray: Bool)? {
            var text = rawTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasSuffix("?") {
                text.removeLast()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let isArray = text.hasPrefix("[") && text.hasSuffix("]")
            if isArray {
                text.removeFirst()
                text.removeLast()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let qualifiedNestedName = "\(ownerTypeName).\(text)"
            if activeConstructsByName[qualifiedNestedName] != nil {
                return (qualifiedNestedName, isArray)
            }

            if activeConstructsByName[text] != nil {
                return (text, isArray)
            }

            if syntaxResolver.declaration(named: text, conformsTo: "Syntax")
                || syntaxResolver.declaration(named: text, conformsTo: "SupportsRewrite")
            {
                return (text, isArray)
            }

            return nil
        }

        func collectRewritePaths(
            for typeName: String,
            path: String,
            activeTypes: Set<String>
        ) {
            if supportsRewrite(typeName) {
                paths.insert("\(path).rewrite")
            }

            guard !activeTypes.contains(typeName) else {
                return
            }

            guard let construct = activeConstructsByName[typeName] else {
                return
            }

            let nextActiveTypes = activeTypes.union([typeName])

            for value in construct.values {
                guard
                    let resolvedType = resolvedValueType(
                        named: value.typeName,
                        ownerTypeName: typeName
                    )
                else {
                    continue
                }

                let valuePath = "\(path).\(value.name)"
                if resolvedType.isArray {
                    collectRewritePaths(
                        for: resolvedType.typeName,
                        path: "\(valuePath)[]",
                        activeTypes: nextActiveTypes
                    )
                } else {
                    collectRewritePaths(
                        for: resolvedType.typeName,
                        path: valuePath,
                        activeTypes: nextActiveTypes
                    )
                }
            }
        }

        collectRewritePaths(for: targetName, path: targetBinding, activeTypes: [])
        return paths
    }

    static func normalizedRewritePath(
        _ name: String,
        targetBinding: String
    ) -> String? {
        let directPath = "\(targetBinding).rewrite"
        if name == directPath {
            return directPath
        }

        let prefix = "\(targetBinding)."
        let suffix = ".rewrite"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
            return nil
        }

        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end else {
            return nil
        }

        let raw = name[start..<end]
        if raw.isEmpty {
            return directPath
        }

        var normalized = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "[" {
                normalized += "[]"
                while index < raw.endIndex, raw[index] != "]" {
                    index = raw.index(after: index)
                }
                if index < raw.endIndex {
                    index = raw.index(after: index)
                }
                continue
            }

            normalized.append(character)
            index = raw.index(after: index)
        }

        return "\(targetBinding).\(normalized).rewrite"
    }

    static func validateRewriteSites(
        for macro: MacroDeclaration,
        targetKind: MacroTargetKind
    ) throws {
        let targetBinding = macro.bindings.target
        let targetPrefix = "\(targetBinding)."
        let allowedPaths = allowedRewritePaths(
            targetBinding: targetBinding,
            targetType: macro.target.typeReference
        )

        var invalidPaths: [String] = []
        for expression in macroOperationExpressions(in: macro.body) {
            guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
                continue
            }
            guard name.hasPrefix(targetPrefix), name.hasSuffix(".rewrite") else {
                continue
            }

            guard
                let normalizedPath = normalizedRewritePath(name, targetBinding: targetBinding),
                resolvedRewriteCall(
                    from: expression,
                    targetBinding: targetBinding,
                    targetKind: targetKind
                ) != nil,
                allowedPaths.contains(normalizedPath)
            else {
                invalidPaths.append(name)
                continue
            }
        }

        guard invalidPaths.isEmpty else {
            let allowedDescription: String
            if allowedPaths.isEmpty {
                allowedDescription = "no rewrite paths"
            } else {
                allowedDescription = allowedPaths.sorted().joined(separator: ", ")
            }
            throw ParseError(
                "Macro #\(macro.name) targeting \(macro.target.typeReference.displayName) uses unsupported rewrite site '\(invalidPaths[0])'. Allowed: \(allowedDescription)."
            )
        }
    }

    static func resolvedRewriteCall(
        from expression: Expression,
        targetBinding: String,
        targetKind: MacroTargetKind
    ) -> ResolvedRewriteCall? {
        guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
            return nil
        }

        let rewritePaths: [(String, ResolvedRewriteSite)]
        switch targetKind {
        case .expression, .block:
            rewritePaths = [
                ("\(targetBinding).rewrite", .targetDirect)
            ]
        case .initializer:
            rewritePaths = [
                ("\(targetBinding).application.rewrite", .initApplication)
            ]
        case .function:
            rewritePaths = [
                ("\(targetBinding).application.rewrite", .functionApplication)
            ]
        case .construct:
            rewritePaths = []
        case .parameter:
            rewritePaths = [
                ("\(targetBinding).declaration.type.rewrite", .parameterDeclarationType),
                ("\(targetBinding).application.expression.rewrite", .parameterApplicationArgument),
            ]
        case .other:
            rewritePaths = []
        }

        if let site = rewritePaths.first(where: { $0.0 == name })?.1 {
            return ResolvedRewriteCall(site: site, payload: arguments[0].value)
        }

        if targetKind == .parameter,
            indexedReference(
                name,
                prefix: "\(targetBinding).application.arguments[",
                suffix: "].rewrite"
            ) != nil
        {
            return ResolvedRewriteCall(
                site: .parameterApplicationArgument, payload: arguments[0].value)
        }

        if targetKind == .initializer,
            indexedReference(
                name,
                prefix: "\(targetBinding).application.arguments[",
                suffix: "].rewrite"
            ) != nil
        {
            return ResolvedRewriteCall(site: .initApplication, payload: arguments[0].value)
        }

        if targetKind == .function,
            indexedReference(
                name,
                prefix: "\(targetBinding).application.arguments[",
                suffix: "].expression.rewrite"
            ) != nil
        {
            return ResolvedRewriteCall(
                site: .functionArgumentExpression,
                payload: arguments[0].value
            )
        }

        return nil
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
        case .background(let body):
            return [
                .background(
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
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
                            value: switchCase.value,
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
