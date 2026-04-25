extension MacroExpander {
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
        case .expand(let targetPath, let emitted):
            return .expand(
                targetPath: targetPath,
                block:
                EmittedCodeBlock(
                    parts: emitted.parts.map { part in
                        switch part {
                        case .text:
                            return part
                        case .splice(let expression, let expected):
                            return .splice(
                                expression: substituteMacroBindings(in: expression, bindings: bindings),
                                expected: expected
                            )
                        }
                    }
                )
            )
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
        case .deferBlock(let deferred):
            return .deferBlock(
                DeferredBlock(body: substituteMacroBindings(in: deferred.body, bindings: bindings))
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
                targetType: macro.target.typeReference
            ) != nil
        }
        return operationExpressions.compactMap {
            context.resolvedRewriteCall(
                from: $0,
                targetBinding: targetBinding,
                targetType: macro.target.typeReference
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
        case .deferBlock(let deferred):
            return [
                .deferBlock(
                    DeferredBlock(body: substituteMacroTargetCalls(
                        in: deferred.body,
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
