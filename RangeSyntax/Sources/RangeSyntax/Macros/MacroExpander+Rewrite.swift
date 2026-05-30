extension MacroExpander {
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
                "Literal macro @literal for \(bridge.initTarget.constructName) could not be interpreted through declaration/call rewrite semantics."
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
        guard let macro = macros[macroName],
            macroTargetAllowsAny(macro.target!, kinds: [.initializer, .function])
        else {
            return nil
        }

        guard let rewriteExpression = try initRewriteExpression(for: macro, context: context) else {
            return nil
        }

        return executeInitRewriteExpression(
            rewriteExpression,
            targetBinding: macro.bindings!.target,
            applicationArguments: applicationArguments,
            initTarget: initTarget
        )
    }

    static func initRewriteExpression(
        for macro: MacroDeclaration,
        context: MacroExpansionContext
    ) throws -> Expression? {
        for rewrite in try resolvedRewriteCalls(for: macro, context: context)
        where rewrite.site == .initApplication || rewrite.site == .functionApplication
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
                macroTargetAllows(macro.target!, kind: .initializer)
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

            let targetBinding = macro.bindings!.target
            var bindings: [String: Expression] = [
                "\(targetBinding).call.arguments": .array(callArguments.map(\.value))
            ]
            for (index, argument) in callArguments.enumerated() {
                bindings["\(targetBinding).call.arguments[\(index)].expression"] =
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
        let wholePrefixes = [
            "\(targetBinding).application.arguments[",
            "\(targetBinding).call.arguments[",
        ]
        let expressionPrefixes = [
            "\(targetBinding).application.arguments[",
            "\(targetBinding).call.arguments[",
        ]

        for prefix in wholePrefixes {
            if let index = indexedReference(identifier, prefix: prefix, suffix: "]") {
                guard applicationArguments.indices.contains(index) else {
                    return nil
                }
                return applicationArguments[index]
            }
        }

        for prefix in expressionPrefixes {
            if let index = indexedReference(
                identifier,
                prefix: prefix,
                suffix: "].expression"
            ) {
                guard applicationArguments.indices.contains(index) else {
                    return nil
                }
                let argument = applicationArguments[index]
                return CallArgument(label: argument.label, value: argument.value)
            }
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
        construct: ConstructDeclaration,
        applications: [MacroApplication],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws {
        for application in applications {
            if application.name == "package" || application.name == "syntax" {
                continue
            }
            guard let macro = macros[application.name] else {
                if let marker = context.markerDeclarationsByName[application.name] {
                    guard macroTargetAllows(marker.target, kind: .construct) else {
                        throw ParseError(
                            "Marker #\(application.name) is used on a construct but targets \(marker.target.displayName)."
                        )
                    }
                    _ = try parseMarkerArgumentBindings(
                        for: marker,
                        argumentClause: application.argumentClause,
                        rawBody: application.rawBody
                    )
                    let targetValue = MacroTargetValueBuilder().targetValue(for: construct)
                    try emitMarkerDiagnostics(
                        from: marker.body,
                        marker: marker,
                        targetValue: targetValue,
                        context: context
                    )
                    if marker.valueType.isMarkerEffect {
                        continue
                    }
                    _ = try MacroTargetValueBuilder.evaluateMarkerValue(
                        for: application,
                        marker: marker,
                        targetValue: targetValue,
                        context: context
                    )
                    continue
                }
                throw ParseError("Unknown attached macro @\(application.name).")
            }
            guard macroTargetAllows(macro.target!, kind: .construct) else {
                throw ParseError(
                    "Macro #\(application.name) is used on a construct but targets \(macro.target!.displayName)."
                )
            }
            try emitMacroDiagnostics(
                from: macro.body,
                macro: macro,
                targetValue: MacroTargetValueBuilder(
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    markerDeclarationsByName: context.markerDeclarationsByName
                ).targetValue(for: construct),
                context: context
            )
            if !macroOperationExpressions(in: macro.body).isEmpty {
                _ = try resolvedRewriteCalls(for: macro, context: context)
            }
        }
    }

    static func validateExtensionMacros(
        extensionDeclaration: ExtensionDeclaration,
        applications: [MacroApplication],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws {
        for application in applications {
            guard let macro = macros[application.name] else {
                if let marker = context.markerDeclarationsByName[application.name] {
                    guard macroTargetAllows(marker.target, kind: .typeExtension) else {
                        throw ParseError(
                            "Marker #\(application.name) is used on an extension but targets \(marker.target.displayName)."
                        )
                    }
                    _ = try parseMarkerArgumentBindings(
                        for: marker,
                        argumentClause: application.argumentClause,
                        rawBody: application.rawBody
                    )
                    if marker.valueType.isMarkerEffect {
                        continue
                    }
                    _ = try MacroTargetValueBuilder.evaluateMarkerValue(
                        for: application,
                        marker: marker,
                        targetValue: MacroTargetValueBuilder(
                            markerDeclarationsByName: context.markerDeclarationsByName,
                            writtenSyntaxByID: context.graphContext.writtenSyntaxByID
                        ).targetValue(for: extensionDeclaration),
                        context: context
                    )
                    continue
                }
                throw ParseError("Unknown attached macro @\(application.name).")
            }
            guard macroTargetAllows(macro.target!, kind: .typeExtension) else {
                throw ParseError(
                    "Macro #\(application.name) is used on an extension but targets \(macro.target!.displayName)."
                )
            }
            try emitMacroDiagnostics(from: macro.body, macro: macro, context: context)
            if !macroOperationExpressions(in: macro.body).isEmpty {
                _ = try resolvedRewriteCalls(for: macro, context: context)
            }
        }
    }

    static func applyAttachedParameterTypeRewrite(
        macro: MacroDeclaration,
        to typeReference: TypeReference,
        context: MacroExpansionContext
    ) throws -> TypeReference {
        try emitMacroDiagnostics(from: macro.body, macro: macro, context: context)
        let targetBinding = macro.bindings!.target
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
        try emitMacroDiagnostics(from: macro.body, macro: macro, context: context)
        let targetBinding = macro.bindings!.target
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
        let targetBinding = macro.bindings!.target
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
            case .expand:
                continue
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
            case .deferBlock(let deferred):
                expressions.append(contentsOf: macroOperationExpressions(in: deferred.body))
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
                .break, .continue:
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

    static func closureComponents(from expression: Expression) -> (parameters: [String], body: [Statement])? {
        guard case .call(let name, let arguments) = expression, name == "Closure" else {
            return nil
        }

        let parameterArgument = arguments.first(where: { $0.label == "parameters" })
            ?? (arguments.count >= 1 ? arguments[0] : nil)
        let bodyArgument = arguments.first(where: { $0.label == "body" })
            ?? (arguments.count >= 2 ? arguments[1] : nil)

        guard
            let parameterArgument,
            let bodyArgument,
            case .array(let parameterExpressions) = parameterArgument.value,
            case .block(let body) = bodyArgument.value
        else {
            return nil
        }

        let parameters = parameterExpressions.compactMap { expression -> String? in
            guard case .identifier(let name) = expression else {
                return nil
            }
            return name
        }

        guard parameters.count == parameterExpressions.count else {
            return nil
        }

        return (parameters, body)
    }

    static func propertyTransformRegistrations(for macro: MacroDeclaration) throws -> [PropertyTransformRegistration] {
        let targetBinding = macro.bindings!.target
        let operationExpressions = macroOperationExpressions(in: macro.body)
        var registrations: [PropertyTransformRegistration] = []

        for expression in operationExpressions {
            guard case .call(let name, let arguments) = expression, arguments.count == 1 else {
                continue
            }

            let hook: PropertyTransformHook?
            switch name {
            case "\(targetBinding).initializer":
                hook = .initializer
            case "\(targetBinding).getter":
                hook = .getter
            case "\(targetBinding).setter":
                hook = .setter
            default:
                hook = nil
            }

            guard let hook else {
                continue
            }

            guard let closure = closureComponents(from: arguments[0].value) else {
                throw ParseError(
                    "Macro #\(macro.name) \(name)(...) must receive a closure."
                )
            }

            guard closure.parameters.count == 1 else {
                throw ParseError(
                    "Macro #\(macro.name) \(name)(...) must receive a single-parameter closure."
                )
            }

            let bodyExpression = try closureResultExpression(
                from: closure.body,
                macroName: macro.name,
                hookName: name
            )

            registrations.append(
                PropertyTransformRegistration(
                    hook: hook,
                    parameterName: closure.parameters[0],
                    body: bodyExpression
                )
            )
        }

        return registrations
    }

    static func closureResultExpression(
        from statements: [Statement],
        macroName: String,
        hookName: String
    ) throws -> Expression {
        guard statements.count == 1 else {
            throw ParseError(
                "Macro #\(macroName) \(hookName)(...) closure must contain exactly one expression."
            )
        }

        switch statements[0] {
        case .expression(let expression):
            return expression
        case .return(let expression?):
            return expression
        default:
            throw ParseError(
                "Macro #\(macroName) \(hookName)(...) closure must evaluate to an expression."
            )
        }
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
                    "Macro #\(macro.name) target.replace(with: ...) must receive a block expression."
                )
            }
            rewriteCalls.append(body)
        }

        guard let rewriteBody = rewriteCalls.first else {
            throw ParseError(
                "Macro #\(macro.name) must call \(macro.bindings!.target).replace(with: ...) with a block expression."
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
                "Macro #\(macro.name) must call \(macro.bindings!.target).replace(with: ...) with an expression."
            )
        }

        if rewriteExpressions.count > 1 {
            throw ParseError("Macro #\(macro.name) can only rewrite once in this bootstrap pass.")
        }

        return rewriteExpression
    }
}
