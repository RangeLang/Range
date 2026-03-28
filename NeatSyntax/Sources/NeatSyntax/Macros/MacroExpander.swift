import Foundation

struct AutoclosureCallableSignature {
    let name: String
    let labels: [String?]
    let autoclosureParameterIndices: Set<Int>
}

public enum MacroExpander {
    public static func expand(files: [ParsedSourceFile]) throws -> [ParsedSourceFile] {
        let registry = collectMacros(from: files)
        let autoclosureCallables = collectAutoclosureCallables(from: files)
        return try files.map { parsedFile in
            ParsedSourceFile(
                path: parsedFile.path,
                sourceFile: try expand(
                    sourceFile: parsedFile.sourceFile,
                    macros: registry,
                    autoclosureCallables: autoclosureCallables
                )
            )
        }
    }

    static func expand(
        sourceFile: SourceFileNode,
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
    ) throws -> SourceFileNode {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .mainBlock(
                MainBlockNode(
                    body: try expand(
                        statements: mainBlock.body,
                        macros: macros,
                        autoclosureCallables: autoclosureCallables
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
                                autoclosureCallables: autoclosureCallables
                            ))
                    },
                    states: module.states,
                    callables: try module.callables.map {
                        try expand(
                            callable: $0,
                            macros: macros,
                            autoclosureCallables: autoclosureCallables
                        )
                    },
                    constructs: try module.constructs.map {
                        try expand(
                            construct: $0,
                            macros: macros,
                            autoclosureCallables: autoclosureCallables
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
                    autoclosureCallables: autoclosureCallables
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

    static func collectAutoclosureCallables(from files: [ParsedSourceFile])
        -> [AutoclosureCallableSignature]
    {
        files.flatMap { parsedFile in
            callablesWithAutoclosure(in: parsedFile.sourceFile)
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

    static func callablesWithAutoclosure(in sourceFile: SourceFileNode)
        -> [AutoclosureCallableSignature]
    {
        switch sourceFile {
        case .module(let module):
            return module.callables.compactMap(autoclosureSignature(for:))
        default:
            return []
        }
    }

    static func autoclosureSignature(for callable: CallableDeclaration)
        -> AutoclosureCallableSignature?
    {
        guard callable.targetType == nil else {
            return nil
        }

        let indices = Set(
            callable.parameters.enumerated().compactMap { index, parameter in
                parameter.macros.contains(where: { $0.name == "autoclosure" }) ? index : nil
            })

        guard !indices.isEmpty else {
            return nil
        }

        return AutoclosureCallableSignature(
            name: callable.name,
            labels: callable.parameters.map(\.externalLabel),
            autoclosureParameterIndices: indices
        )
    }

    static func expand(
        construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
    ) throws
        -> ConstructDeclaration
    {
        ConstructDeclaration(
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
                try expand(derived: $0, macros: macros, autoclosureCallables: autoclosureCallables)
            },
            values: construct.values,
            initializers: try construct.initializers.map {
                try expand(
                    initializer: $0,
                    macros: macros,
                    autoclosureCallables: autoclosureCallables
                )
            },
            callables: try construct.callables.map {
                try expand(
                    callable: $0,
                    macros: macros,
                    autoclosureCallables: autoclosureCallables
                )
            }
        )
    }

    static func expand(
        callable: CallableDeclaration,
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
    ) throws
        -> CallableDeclaration
    {
        CallableDeclaration(
            macros: callable.macros,
            targetType: callable.targetType,
            name: callable.name,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: expand(parameters: callable.parameters),
            returnType: callable.returnType,
            body: try callable.body.map {
                try expand(
                    statements: $0,
                    macros: macros,
                    autoclosureCallables: autoclosureCallables
                )
            }
        )
    }

    static func expand(
        initializer: InitializerDeclaration,
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
    )
        throws
        -> InitializerDeclaration
    {
        InitializerDeclaration(
            macros: initializer.macros,
            parameters: expand(parameters: initializer.parameters),
            body: try initializer.body.map {
                try expand(
                    statements: $0,
                    macros: macros,
                    autoclosureCallables: autoclosureCallables
                )
            }
        )
    }

    static func expand(
        derived: DerivedDeclaration,
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
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
                    autoclosureCallables: autoclosureCallables
                )
            }
        )
    }

    static func expand(
        statements: [Statement],
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
    ) throws
        -> [Statement]
    {
        var expanded: [Statement] = []
        for statement in statements {
            expanded.append(
                contentsOf: try expand(
                    statement: statement,
                    macros: macros,
                    autoclosureCallables: autoclosureCallables
                ))
        }
        return expanded
    }

    static func expand(
        statement: Statement,
        macros: [String: MacroDeclaration],
        autoclosureCallables: [AutoclosureCallableSignature]
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
                autoclosureCallables: autoclosureCallables
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
                autoclosureCallables: autoclosureCallables
            )
        case .derived(let name, let typeName, let body):
            return [
                .derived(
                    name: name, typeName: typeName,
                    body: try expand(
                        statements: body,
                        macros: macros,
                        autoclosureCallables: autoclosureCallables
                    ))
            ]
        case .forEach(let name, let sequence, let body):
            return [
                .forEach(
                    name: name,
                    sequence: expand(
                        expression: sequence, autoclosureCallables: autoclosureCallables),
                    body: try expand(
                        statements: body,
                        macros: macros,
                        autoclosureCallables: autoclosureCallables
                    ))
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: expand(
                        expression: condition,
                        autoclosureCallables: autoclosureCallables
                    ),
                    body: try expand(
                        statements: body,
                        macros: macros,
                        autoclosureCallables: autoclosureCallables
                    ))
            ]
        case .conditional(let branches):
            return [
                .conditional(
                    try branches.map { branch in
                        StatementConditionalBranch(
                            condition: branch.condition.map {
                                expand(expression: $0, autoclosureCallables: autoclosureCallables)
                            },
                            body: try expand(
                                statements: branch.body,
                                macros: macros,
                                autoclosureCallables: autoclosureCallables
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
                        autoclosureCallables: autoclosureCallables
                    )
                )
            ]
        case .assignment(let target, let expression):
            return [
                .assignment(
                    target: target,
                    expression: expand(
                        expression: expression,
                        autoclosureCallables: autoclosureCallables
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
                        autoclosureCallables: autoclosureCallables
                    )
                )
            ]
        case .expression(let expression):
            return [
                .expression(
                    expand(expression: expression, autoclosureCallables: autoclosureCallables))
            ]
        case .return(let expression):
            return [
                .return(
                    expression.map {
                        expand(expression: $0, autoclosureCallables: autoclosureCallables)
                    })
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: expand(
                        expression: expression,
                        autoclosureCallables: autoclosureCallables
                    ),
                    cases: try cases.map { switchCase in
                        SwitchCase(
                            value: expand(
                                expression: switchCase.value,
                                autoclosureCallables: autoclosureCallables
                            ),
                            body: try expand(
                                statements: switchCase.body,
                                macros: macros,
                                autoclosureCallables: autoclosureCallables
                            )
                        )
                    },
                    defaultBody: try defaultBody.map {
                        try expand(
                            statements: $0,
                            macros: macros,
                            autoclosureCallables: autoclosureCallables
                        )
                    }
                )
            ]
        default:
            return [statement]
        }
    }

    static func expand(parameters: [NeatFunctionParameter]) -> [NeatFunctionParameter] {
        parameters.map { parameter in
            guard parameter.macros.contains(where: { $0.name == "autoclosure" }),
                let typeReference = parameter.typeReference
            else {
                return parameter
            }

            return NeatFunctionParameter(
                macros: parameter.macros,
                localName: parameter.localName,
                externalLabel: parameter.externalLabel,
                typeReference: .function(parameters: [], returnType: typeReference),
                slotName: parameter.slotName
            )
        }
    }

    static func expand(
        expression: Expression,
        autoclosureCallables: [AutoclosureCallableSignature]
    ) -> Expression {
        switch expression {
        case .call(let name, let arguments):
            let rewrittenArguments = arguments.map { argument in
                CallArgument(
                    label: argument.label,
                    value: expand(
                        expression: argument.value,
                        autoclosureCallables: autoclosureCallables
                    )
                )
            }

            guard
                let signature = matchingAutoclosureCallable(
                    name: name,
                    arguments: rewrittenArguments,
                    signatures: autoclosureCallables
                )
            else {
                return .call(name: name, arguments: rewrittenArguments)
            }

            let wrappedArguments = rewrittenArguments.enumerated().map { index, argument in
                guard signature.autoclosureParameterIndices.contains(index) else {
                    return argument
                }
                return CallArgument(
                    label: argument.label,
                    value: .block([.expression(argument.value)])
                )
            }

            return .call(name: name, arguments: wrappedArguments)
        case .array(let elements):
            return .array(
                elements.map { expand(expression: $0, autoclosureCallables: autoclosureCallables) }
            )
        case .dictionary(let elements):
            return .dictionary(
                elements.map { element in
                    DictionaryElement(
                        key: expand(
                            expression: element.key,
                            autoclosureCallables: autoclosureCallables
                        ),
                        value: expand(
                            expression: element.value,
                            autoclosureCallables: autoclosureCallables
                        )
                    )
                }
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            return .ternary(
                condition: expand(
                    expression: condition, autoclosureCallables: autoclosureCallables),
                trueExpression: expand(
                    expression: trueExpression,
                    autoclosureCallables: autoclosureCallables
                ),
                falseExpression: expand(
                    expression: falseExpression,
                    autoclosureCallables: autoclosureCallables
                )
            )
        case .unary(let operatorSymbol, let nested):
            return .unary(
                operatorSymbol: operatorSymbol,
                expression: expand(expression: nested, autoclosureCallables: autoclosureCallables)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: expand(expression: lhs, autoclosureCallables: autoclosureCallables),
                operatorSymbol: operatorSymbol,
                rhs: expand(expression: rhs, autoclosureCallables: autoclosureCallables)
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
                                expand(
                                    expression: nested,
                                    autoclosureCallables: autoclosureCallables
                                ))
                        }
                    }
                )
            )
        case .block(let body):
            return .block(
                body.flatMap {
                    (try? expand(
                        statement: $0,
                        macros: [:],
                        autoclosureCallables: autoclosureCallables
                    )) ?? [$0]
                }
            )
        case .integer, .double, .string, .boolean, .nilLiteral, .identifier, .bindingReference:
            return expression
        }
    }

    static func matchingAutoclosureCallable(
        name: String,
        arguments: [CallArgument],
        signatures: [AutoclosureCallableSignature]
    ) -> AutoclosureCallableSignature? {
        signatures.first { signature in
            signature.name == name
                && signature.labels.elementsEqual(arguments.map(\.label), by: { $0 == $1 })
        }
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
        try parser.consume(.eof)

        guard arguments.count == parameters.count else {
            throw ParseError(
                "Macro #\(macro.name) expects \(parameters.count) argument(s), got \(arguments.count)."
            )
        }

        var bindings: [String: Expression] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            switch (parameter.externalLabel, argument.label) {
            case (nil, nil):
                break
            case (nil, .some(let label)):
                throw ParseError(
                    "Macro #\(macro.name) argument for \(parameter.localName) should not use label \(label)."
                )
            case (.some(let expected), .some(let actual)) where expected == actual:
                break
            case (.some(let expected), .some(let actual)):
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expected), got \(actual)."
                )
            case (.some(let expected), nil):
                throw ParseError(
                    "Macro #\(macro.name) expects argument label \(expected)."
                )
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
