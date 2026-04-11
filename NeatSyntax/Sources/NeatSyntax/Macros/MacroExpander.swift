import Foundation

struct AttachedParameterMacroSignature {
    let name: String
    let labels: [String?]
    let attachedParameterMacrosByIndex: [Int: MacroDeclaration]
}

enum AttachedParameterRewriteShape {
    case single
    case variadic
}

enum ResolvedRewriteSite {
    case targetDirect
    case initApplication
    case parameterDeclarationType
    case parameterApplicationArguments
    case parameterApplicationArgument
}

struct ResolvedRewriteCall {
    let site: ResolvedRewriteSite
    let payload: Expression
}

public enum MacroExpander {
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
        let attachedLiteralConstructs = declarationGraph.realizedLiteralBridges
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

    public static func collectMacros(from files: [ParsedSourceFile]) -> [String: MacroDeclaration] {
        var registry: [String: MacroDeclaration] = [:]
        for parsedFile in files {
            for macro in self.macros(in: parsedFile.sourceFile) {
                registry[macro.name] = macro
            }
        }
        return registry
    }

    public static func collectMacroExpansionTypes(from files: [ParsedSourceFile])
        -> [String: TypeReference]
    {
        collectMacros(from: files).compactMapValues(\.expansionType)
    }

    static func validateMacroSyntaxCaptures(
        macros: [MacroDeclaration],
        syntaxResolver: DeclarationSyntaxResolver
    ) throws {
        for macro in macros {
            for parameter in macro.parameters {
                guard syntaxResolver.typeConformsToSyntax(parameter.typeReference) else {
                    if parameter.capturesSyntax {
                        throw ParseError(
                            "Macro #\(macro.name) parameter \(parameter.localName) uses capture with non-syntax type \(parameter.typeReference?.displayName ?? "unknown")."
                        )
                    }
                    continue
                }
                guard parameter.capturesSyntax else {
                    throw ParseError(
                        "Macro #\(macro.name) parameter \(parameter.localName) must use capture \(parameter.typeReference?.displayName ?? "syntax") to bind syntax."
                    )
                }
            }
        }
    }

    static func collectAttachedParameterCallables(
        from files: [ParsedSourceFile],
        macros: [String: MacroDeclaration]
    )
        -> [AttachedParameterMacroSignature]
    {
        files.flatMap { parsedFile in
            callablesWithAttachedParameterMacros(in: parsedFile.sourceFile, macros: macros)
        }
    }

    static func macros(in sourceFile: SourceFileNode) -> [MacroDeclaration] {
        switch sourceFile {
        case .macro(let declaration):
            return [declaration]
        case .module(let module):
            return module.macros
        case .construct, .enumeration, .protocolDefinition, .mainBlock, .extensions:
            return []
        }
    }

    static func callablesWithAttachedParameterMacros(
        in sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration]
    )
        -> [AttachedParameterMacroSignature]
    {
        switch sourceFile {
        case .module(let module):
            return module.callables.compactMap {
                attachedParameterMacroSignature(for: $0, macros: macros)
            }
        default:
            return []
        }
    }

    static func attachedParameterMacroSignature(
        for callable: CallableDeclaration,
        macros: [String: MacroDeclaration]
    )
        -> AttachedParameterMacroSignature?
    {
        guard callable.targetType == nil else {
            return nil
        }

        let attachedParameterMacrosByIndex: [Int: MacroDeclaration] = Dictionary(
            uniqueKeysWithValues: callable.parameters.enumerated().compactMap {
                index, parameter -> (Int, MacroDeclaration)? in
                guard
                    let macro = parameter.macros.lazy.compactMap({ macros[$0.name] }).first(where: {
                        $0.target.typeReference.displayName == "Parameter"
                    })
                else { return nil }

                return (index, macro)
            })

        guard !attachedParameterMacrosByIndex.isEmpty else {
            return nil
        }

        return AttachedParameterMacroSignature(
            name: callable.name,
            labels: callable.parameters.map(\.externalLabel),
            attachedParameterMacrosByIndex: attachedParameterMacrosByIndex
        )
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
            parameters: expand(parameters: callable.parameters, macros: macros),
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
            parameters: expand(parameters: initializer.parameters, macros: macros),
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
            guard macro.target.typeReference.displayName == "Block"
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
    ) -> [NeatFunctionParameter] {
        parameters.map { parameter in
            let attachedParameterMacros: [MacroDeclaration] = parameter.macros.compactMap {
                macroApplication in
                guard let macro = macros[macroApplication.name],
                    macro.target.typeReference.displayName == "Parameter"
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

            let rewrittenType = attachedParameterMacros.reduce(typeReference) {
                currentType, macro in
                applyAttachedParameterTypeRewrite(macro: macro, to: currentType)
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

            guard
                let signature = matchingAttachedParameterCallable(
                    name: name,
                    arguments: rewrittenArguments,
                    signatures: attachedParameterCallables
                )
            else {
                return .call(name: name, arguments: rewrittenArguments)
            }

            var wrappedArguments: [CallArgument] = []
            var argumentIndex = 0

            for parameterIndex in signature.labels.indices {
                if let macro = signature.attachedParameterMacrosByIndex[parameterIndex],
                    attachedParameterRewriteShape(for: macro) == .variadic
                {
                    let consumedArguments = Array(rewrittenArguments.dropFirst(argumentIndex))
                    wrappedArguments.append(
                        applyAttachedParameterArgumentRewrite(
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
                        applyAttachedParameterArgumentRewrite(
                            macro: macro,
                            arguments: [argument]
                        )
                    )
                } else {
                    wrappedArguments.append(argument)
                }
                argumentIndex += 1
            }

            return .call(name: name, arguments: wrappedArguments)
        case .freestandingMacro(let name, let arguments):
            guard let macro = macros[name],
                macro.target.typeReference.displayName == "Expression"
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

        guard let rewritten = executeInitMacroRewrite(
            macroName: "literal",
            initTarget: bridge.initTarget,
            applicationArguments: [
                CallArgument(label: bridge.initTarget.parameterLabels.first ?? nil, value: expression)
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
    ) -> Expression? {
        guard let macro = macros[macroName], macro.target.typeReference.displayName == "Init" else {
            return nil
        }

        guard let rewriteExpression = initRewriteExpression(for: macro) else {
            return nil
        }

        return executeInitRewriteExpression(
            rewriteExpression,
            targetBinding: macro.bindings.target,
            applicationArguments: applicationArguments,
            initTarget: initTarget
        )
    }

    static func initRewriteExpression(for macro: MacroDeclaration) -> Expression? {
        for expression in macroOperationExpressions(in: macro.body) {
            guard let rewrite = resolvedRewriteCall(
                from: expression,
                targetBinding: macro.bindings.target
            ),
                rewrite.site == .initApplication
            else {
                continue
            }

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
            guard let argument = resolveInitApplicationArgumentReference(
                value,
                targetBinding: targetBinding,
                applicationArguments: applicationArguments
            ) else {
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
    ) -> AttachedParameterMacroSignature? {
        signatures.first { signature in
            guard signature.name == name else {
                return false
            }

            let variadicIndex = signature.attachedParameterMacrosByIndex
                .sorted { $0.key < $1.key }
                .first { attachedParameterRewriteShape(for: $0.value) == .variadic }?.key

            guard let variadicIndex else {
                return signature.labels.elementsEqual(arguments.map(\.label), by: { $0 == $1 })
            }

            guard variadicIndex == signature.labels.count - 1 else {
                return false
            }

            guard arguments.count >= variadicIndex else {
                return false
            }

            let fixedLabels = Array(signature.labels.prefix(variadicIndex))
            let fixedArgumentLabels = Array(arguments.prefix(variadicIndex)).map(\.label)
            guard fixedLabels.elementsEqual(fixedArgumentLabels, by: { $0 == $1 }) else {
                return false
            }

            let variadicLabel = signature.labels[variadicIndex]
            return arguments.dropFirst(variadicIndex).allSatisfy { $0.label == variadicLabel }
        }
    }

    static func applyAttachedParameterTypeRewrite(
        macro: MacroDeclaration,
        to typeReference: TypeReference
    ) -> TypeReference {
        let targetBinding = macro.bindings.target
        for expression in macroOperationExpressions(in: macro.body) {
            guard let rewrite = resolvedRewriteCall(
                from: expression,
                targetBinding: targetBinding
            ),
                rewrite.site == .parameterDeclarationType
            else {
                continue
            }

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

    static func applyAttachedParameterArgumentRewrite(
        macro: MacroDeclaration,
        arguments: [CallArgument]
    ) -> CallArgument {
        let targetBinding = macro.bindings.target
        let primaryArgument = arguments.first ?? CallArgument(label: nil, value: .array([]))

        for expression in macroOperationExpressions(in: macro.body) {
            guard let rewrite = resolvedRewriteCall(
                from: expression,
                targetBinding: targetBinding
            ),
                rewrite.site == .parameterApplicationArguments
                    || rewrite.site == .parameterApplicationArgument
            else {
                continue
            }

            let substituted = substituteMacroBindings(
                in: rewrite.payload,
                bindings: [
                    "\(targetBinding).application.arguments[0].expression": primaryArgument.value,
                    "\(targetBinding).application.arguments": .array(arguments.map(\.value)),
                ]
            )

            return CallArgument(
                label: primaryArgument.label,
                value: interpretAttachedParameterArgumentRewriteExpression(substituted)
            )
        }

        return primaryArgument
    }

    static func attachedParameterRewriteShape(
        for macro: MacroDeclaration
    ) -> AttachedParameterRewriteShape {
        let targetBinding = macro.bindings.target
        for expression in macroOperationExpressions(in: macro.body) {
            guard let rewrite = resolvedRewriteCall(
                from: expression,
                targetBinding: targetBinding
            ),
                rewrite.site == .parameterApplicationArguments
                    || rewrite.site == .parameterApplicationArgument
            else {
                continue
            }

            if case .identifier(let identifier) = rewrite.payload,
                identifier == "\(targetBinding).application.arguments"
            {
                return .variadic
            }
        }

        return .single
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

        for statement in macro.body {
            guard case .expression(let expression) = statement,
                let rewrite = resolvedRewriteCall(
                    from: expression,
                    targetBinding: macro.bindings.target
                ),
                rewrite.site == .targetDirect
            else {
                continue
            }
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

        for statement in macro.body {
            guard case .expression(let expression) = statement,
                let rewrite = resolvedRewriteCall(
                    from: expression,
                    targetBinding: macro.bindings.target
                ),
                rewrite.site == .targetDirect
            else {
                continue
            }
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

    static func expressionMacroArgumentBindings(
        for macro: MacroDeclaration,
        arguments: [CallArgument]
    ) throws -> [String: Expression] {
        let parameters = macro.parameters
        guard arguments.count == parameters.count else {
            throw ParseError(
                "Macro #\(macro.name) expects \(parameters.count) argument(s), got \(arguments.count)."
            )
        }

        var bindings: [String: Expression] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            let expectedLabel = macroArgumentLabel(for: parameter)
            let actualLabel = argument.label

            if actualLabel == nil {
                // Macro arguments can be passed positionally.
            } else if let expectedLabel, let actualLabel, expectedLabel == actualLabel {
                // Label matched.
            } else if let expectedLabel, let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expectedLabel), got \(actualLabel)."
                )
            } else if let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) argument for \(parameter.localName) should not use label \(actualLabel)."
                )
            }

            bindings[parameter.localName] = argument.value
        }

        return bindings
    }

    static func parseMacroArgumentBindings(
        for macro: MacroDeclaration,
        argumentClause: String?
    ) throws -> [String: Expression] {
        let parameters = macro.parameters
        guard !parameters.isEmpty || argumentClause == nil else {
            throw ParseError("Macro #\(macro.name) requires arguments.")
        }
        guard !parameters.isEmpty else {
            return [:]
        }
        guard let argumentClause else {
            throw ParseError("Macro #\(macro.name) requires arguments.")
        }

        var parser = try Parser(source: "macro(\(argumentClause))")
        _ = try parser.consumeCallableName()
        let arguments = try parser.parseInvocationArgumentsIfPresent()
        try parser.consume(Token.eof)

        guard arguments.count == parameters.count else {
            throw ParseError(
                "Macro #\(macro.name) expects \(parameters.count) argument(s), got \(arguments.count)."
            )
        }

        var bindings: [String: Expression] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            let expectedLabel = macroArgumentLabel(for: parameter)
            let actualLabel = argument.label

            if actualLabel == nil {
                // Macro arguments can be passed positionally.
            } else if let expectedLabel, let actualLabel, expectedLabel == actualLabel {
                // Label matched.
            } else if let expectedLabel, let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expectedLabel), got \(actualLabel)."
                )
            } else if let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) argument for \(parameter.localName) should not use label \(actualLabel)."
                )
            }
            bindings[parameter.localName] = argument.value
        }
        return bindings
    }

    static func macroArgumentLabel(for parameter: NeatFunctionParameter) -> String? {
        parameter.externalLabel ?? parameter.localName
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
        switch expression {
        case .identifier(let name):
            if let bound = bindings[name] {
                return bound
            }
            return .named(name)
        case .call(let name, let arguments):
            if name == "TypeReference.array",
                arguments.count == 1,
                arguments[0].label == "element" || arguments[0].label == nil,
                let element = interpretTypeReferenceRewriteExpression(
                    arguments[0].value,
                    bindings: bindings
                )
            {
                return .array(element)
            }

            if name == "TypeReference.function",
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

            return nil
        default:
            return nil
        }
    }

    static func resolvedRewriteCall(
        from expression: Expression,
        targetBinding: String
    ) -> ResolvedRewriteCall? {
        guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
            return nil
        }

        let site: ResolvedRewriteSite?
        switch name {
        case "\(targetBinding).rewrite":
            site = .targetDirect
        case "\(targetBinding).application.rewrite":
            site = .initApplication
        case "\(targetBinding).declaration.type.rewrite":
            site = .parameterDeclarationType
        case "\(targetBinding).application.arguments.rewrite":
            site = .parameterApplicationArguments
        case "\(targetBinding).application.argument.rewrite":
            site = .parameterApplicationArgument
        default:
            site = nil
        }

        guard let site else {
            return nil
        }

        return ResolvedRewriteCall(site: site, payload: arguments[0].value)
    }

    static func renderExpressionForStringify(_ expression: Expression) -> String {
        switch expression {
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return "\"\(value)\""
        case .interpolatedString(let string):
            let renderedSegments = string.segments.map { segment in
                switch segment {
                case .text(let text):
                    return text
                case .expression(let expression):
                    return "\\(\(renderExpressionForStringify(expression)))"
                }
            }.joined()
            return "\"\(renderedSegments)\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .freestandingMacro(let name, let arguments):
            return "#\(name)(\(renderArgumentsForStringify(arguments)))"
        case .block:
            return "{ ... }"
        case .identifier(let name):
            return name
        case .call(let name, let arguments):
            return "\(name)(\(renderArgumentsForStringify(arguments)))"
        case .bindingReference(let name):
            return "$\(name)"
        case .array(let elements):
            return "[\(elements.map(renderExpressionForStringify).joined(separator: ", "))]"
        case .dictionary(let elements):
            let rendered = elements.map {
                "\(renderExpressionForStringify($0.key)): \(renderExpressionForStringify($0.value))"
            }.joined(separator: ", ")
            return "[\(rendered)]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(renderExpressionForStringify(condition)) ? \(renderExpressionForStringify(trueExpression)) : \(renderExpressionForStringify(falseExpression))"
        case .unary(let operatorSymbol, let expression):
            return "\(operatorSymbol.rawValue)\(renderExpressionForStringify(expression))"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return
                "\(renderExpressionForStringify(lhs)) \(operatorSymbol.rawValue) \(renderExpressionForStringify(rhs))"
        }
    }

    private static func renderArgumentsForStringify(_ arguments: [CallArgument]) -> String {
        arguments.map { argument in
            let renderedValue = renderExpressionForStringify(argument.value)
            if let label = argument.label {
                return "\(label): \(renderedValue)"
            }
            return renderedValue
        }.joined(separator: ", ")
    }

    static func interpretExpressionMacroRewrite(
        _ expression: Expression,
        bindings: [String: Expression]
    ) -> Expression {
        guard case .interpolatedString(let string) = expression else {
            return expression
        }

        let rendered = string.segments.map { segment in
            switch segment {
            case .text(let text):
                return text
            case .expression(let expression):
                if let boundExpression = macroBoundExpression(from: expression, bindings: bindings) {
                    return renderExpressionForStringify(boundExpression)
                }
                return "\\(\(renderExpressionForStringify(expression)))"
            }
        }.joined()
        return .string(rendered)
    }

    static func macroBoundExpression(
        from expression: Expression,
        bindings: [String: Expression]
    ) -> Expression? {
        guard case .identifier(let name) = expression else {
            return nil
        }
        return bindings[name]
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
