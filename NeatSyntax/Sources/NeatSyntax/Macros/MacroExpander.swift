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

public enum MacroExpander {
    public static func expand(files: [ParsedSourceFile]) throws -> [ParsedSourceFile] {
        let registry = collectMacros(from: files)
        let declarationGraph = DeclarationGraph(files: files)
        let protocols = declarationGraph.protocolsByName
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
                                macros: macros,
                                protocols: protocols,
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
                            ))
                    },
                    states: module.states,
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
                        guard case .attached(let targetType) = $0.target else { return false }
                        return targetType.displayName == "Parameter"
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
            states: construct.states,
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
            targetType: callable.targetType,
            name: callable.name,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: expand(parameters: callable.parameters, macros: macros),
            returnType: callable.returnType,
            body: try callable.body.map {
                try expand(
                    statements: $0,
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
                    macros: macros,
                    protocols: protocols,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            }
        )
    }

    static func expand(
        statements: [Statement],
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
                throw ParseError("Unknown freestanding macro #\(name).")
            }
            guard case .freestanding(let targetType) = macro.target,
                targetType.displayName == "Block"
            else {
                throw ParseError("Macro #\(name) is not a Freestanding<Block> macro.")
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
                    sequence: expand(
                        expression: sequence,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ),
                    body: try expand(
                        statements: body,
                        macros: macros,
                        protocols: protocols,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ))
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: expand(
                        expression: condition,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ),
                    body: try expand(
                        statements: body,
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
                            condition: branch.condition.map {
                                expand(
                                    expression: $0,
                                    attachedParameterCallables: attachedParameterCallables,
                                    attachedLiteralConstructs: attachedLiteralConstructs)
                            },
                            body: try expand(
                                statements: branch.body,
                                macros: macros,
                                protocols: protocols,
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
                            )
                        )
                    }
                )
            ]
        case .declaration(let kind, let name, let typeName, let expression):
            return [
                .declaration(
                    kind: kind,
                    name: name,
                    typeName: typeName,
                    expression: expand(
                        expression: expression,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )
                )
            ]
        case .assignment(let target, let expression):
            return [
                .assignment(
                    target: target,
                    expression: expand(
                        expression: expression,
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
                    expression: expand(
                        expression: expression,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )
                )
            ]
        case .expression(let expression):
            return [
                .expression(
                    expand(
                        expression: expression,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs))
            ]
        case .return(let expression):
            return [
                .return(
                    expression.map {
                        expand(
                            expression: $0,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs)
                    })
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: expand(
                        expression: expression,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    ),
                    cases: try cases.map { switchCase in
                        SwitchCase(
                            value: expand(
                                expression: switchCase.value,
                                attachedParameterCallables: attachedParameterCallables,
                                attachedLiteralConstructs: attachedLiteralConstructs
                            ),
                            body: try expand(
                                statements: switchCase.body,
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
                guard let macro = macros[macroApplication.name] else {
                    return nil
                }
                guard case .attached(let targetType) = macro.target,
                    targetType.displayName == "Parameter"
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
                slotName: parameter.slotName
            )
        }
    }

    static func expand(
        expression: Expression,
        attachedParameterCallables: [AttachedParameterMacroSignature],
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) -> Expression {
        switch expression {
        case .call(let name, let arguments):
            let rewrittenArguments = arguments.map { argument in
                CallArgument(
                    label: argument.label,
                    value: expand(
                        expression: argument.value,
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
        case .array(let elements):
            return .array(
                elements.map {
                    expand(
                        expression: $0,
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )
                }
            )
        case .dictionary(let elements):
            return .dictionary(
                elements.map { element in
                    DictionaryElement(
                        key: expand(
                            expression: element.key,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        ),
                        value: expand(
                            expression: element.value,
                            attachedParameterCallables: attachedParameterCallables,
                            attachedLiteralConstructs: attachedLiteralConstructs
                        )
                    )
                }
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            return .ternary(
                condition: expand(
                    expression: condition,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs),
                trueExpression: expand(
                    expression: trueExpression,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                ),
                falseExpression: expand(
                    expression: falseExpression,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs
                )
            )
        case .unary(let operatorSymbol, let nested):
            return .unary(
                operatorSymbol: operatorSymbol,
                expression: expand(
                    expression: nested,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: expand(
                    expression: lhs,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs),
                operatorSymbol: operatorSymbol,
                rhs: expand(
                    expression: rhs,
                    attachedParameterCallables: attachedParameterCallables,
                    attachedLiteralConstructs: attachedLiteralConstructs)
            )
        case .interpolatedString(let string):
            let expanded: Expression = .interpolatedString(
                InterpolatedString(
                    segments: string.segments.map { segment in
                        switch segment {
                        case .text:
                            return segment
                        case .expression(let nested):
                            return .expression(
                                expand(
                                    expression: nested,
                                    attachedParameterCallables: attachedParameterCallables,
                                    attachedLiteralConstructs: attachedLiteralConstructs
                                ))
                        }
                    }
                )
            )
            return lowerLiteralExpressionIfPossible(
                expanded,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        case .block(let body):
            return .block(
                body.flatMap {
                    (try? expand(
                        statement: $0,
                        macros: [:],
                        protocols: [:],
                        attachedParameterCallables: attachedParameterCallables,
                        attachedLiteralConstructs: attachedLiteralConstructs
                    )) ?? [$0]
                }
            )
        case .integer, .double, .string, .boolean, .nilLiteral:
            return lowerLiteralExpressionIfPossible(
                expression,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        case .identifier, .bindingReference:
            return expression
        }
    }

    static func lowerLiteralExpressionIfPossible(
        _ expression: Expression,
        attachedLiteralConstructs: [RealizedLiteralBridge]
    ) -> Expression {
        guard let literalType = bootstrapLiteralType(for: expression)
        else {
            return expression
        }

        guard
            let bridge = preferredDefaultLiteralBridge(
                for: literalType.displayName,
                attachedLiteralConstructs: attachedLiteralConstructs
            )
        else {
            return expression
        }

        return .call(
            name: bridge.constructName,
            arguments: [
                CallArgument(label: bridge.parameterLabel, value: expression)
            ]
        )
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
        case .block, .identifier, .call, .bindingReference, .array, .dictionary, .ternary,
            .unary, .binary:
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
        for expression in macroOperationExpressions(in: macro.body) {
            guard case .call(let name, let arguments) = expression,
                name == "\(macro.bindings.target).parameter.type.rewrite"
                    || name == "\(macro.bindings.target).type.rewrite",
                arguments.count == 1
            else {
                continue
            }

            if let rewrittenType = interpretedAttachedParameterTypeRewrite(
                arguments[0].value,
                targetBinding: macro.bindings.target
            ) {
                return rewrittenType.replacingTargetType(with: typeReference)
            }
        }

        return typeReference
    }

    static func applyAttachedParameterArgumentRewrite(
        macro: MacroDeclaration,
        arguments: [CallArgument]
    ) -> CallArgument {
        let primaryArgument = arguments.first ?? CallArgument(label: nil, value: .array([]))

        for expression in macroOperationExpressions(in: macro.body) {
            guard case .call(let name, let rewriteArguments) = expression,
                name == "\(macro.bindings.target).arguments.rewrite"
                    || name == "\(macro.bindings.target).argument.rewrite",
                rewriteArguments.count == 1
            else {
                continue
            }

            let substituted = substituteMacroBindings(
                in: rewriteArguments[0].value,
                bindings: [
                    "\(macro.bindings.target).arguments[0].expression": primaryArgument.value,
                    "\(macro.bindings.target).arguments": .array(arguments.map(\.value)),
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
        for expression in macroOperationExpressions(in: macro.body) {
            guard case .call(let name, let arguments) = expression,
                name == "\(macro.bindings.target).arguments.rewrite"
                    || name == "\(macro.bindings.target).argument.rewrite",
                arguments.count == 1
            else {
                continue
            }

            if case .identifier(let identifier) = arguments[0].value,
                identifier == "\(macro.bindings.target).arguments"
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
            case .declaration, .assignment, .compoundAssignment, .return, .freestandingMacro,
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

    static func interpretedAttachedParameterTypeRewrite(
        _ expression: Expression,
        targetBinding: String
    ) -> AttachedParameterTypeRewrite? {
        guard case .call(let name, let arguments) = expression else {
            return nil
        }

        if name == "FunctionType",
            arguments.count == 2,
            let parametersArgument = arguments.first(where: { $0.label == "parameters" }),
            let returnTypeArgument = arguments.first(where: { $0.label == "returnType" }),
            case .array(let parameterExpressions) = parametersArgument.value,
            parameterExpressions.isEmpty,
            case .identifier(let identifier) = returnTypeArgument.value,
            identifier == "\(targetBinding).parameter.type"
                || identifier == "\(targetBinding).type"
        {
            return .zeroParameterFunctionReturningTarget
        }

        if name == "ArrayType",
            arguments.count == 1,
            arguments[0].label == "element",
            case .identifier(let identifier) = arguments[0].value,
            identifier == "\(targetBinding).parameter.type"
                || identifier == "\(targetBinding).type"
        {
            return .arrayOfTarget
        }

        if name == "Closure",
            arguments.count == 1,
            arguments[0].label == nil,
            case .identifier(let identifier) = arguments[0].value,
            identifier == "\(targetBinding).parameter.type"
                || identifier == "\(targetBinding).type"
        {
            return .zeroParameterFunctionReturningTarget
        }

        return nil
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
            guard case .expression(let expression) = statement else {
                continue
            }
            guard case .call(let name, let arguments) = expression else {
                continue
            }
            guard name == "\(macro.bindings.target).rewrite" else {
                continue
            }
            guard arguments.count == 1 else {
                continue
            }
            guard case .block(let body) = arguments[0].value else {
                throw ParseError(
                    "Macro #\(macro.name) target.rewrite(...) must receive a block expression for Freestanding<Block>."
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
            let expectedLabel = parameter.externalLabel
            let actualLabel = argument.label

            if expectedLabel == nil, actualLabel == nil {
                // No label expected and none provided.
            } else if expectedLabel == nil, let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) argument for \(parameter.localName) should not use label \(actualLabel)."
                )
            } else if let expectedLabel, let actualLabel, expectedLabel == actualLabel {
                // Expected label matched.
            } else if let expectedLabel, let actualLabel {
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expectedLabel), got \(actualLabel)."
                )
            } else if let expectedLabel {
                throw ParseError("Macro #\(macro.name) expects argument label \(expectedLabel).")
            }
            bindings[parameter.localName] = argument.value
        }
        return bindings
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
        case .declaration(let kind, let name, let typeName, let expression):
            return .declaration(
                kind: kind,
                name: name,
                typeName: typeName,
                expression: substituteMacroBindings(in: expression, bindings: bindings)
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

enum AttachedParameterTypeRewrite {
    case zeroParameterFunctionReturningTarget
    case arrayOfTarget

    func replacingTargetType(with typeReference: TypeReference) -> TypeReference {
        switch self {
        case .zeroParameterFunctionReturningTarget:
            return .function(parameters: [], returnType: typeReference)
        case .arrayOfTarget:
            return .array(typeReference)
        }
    }
}
