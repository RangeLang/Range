extension MacroExpander {
    struct EmittedDeclarationBundle {
        var constructs: [ConstructDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var macros: [MacroDeclaration] = []
        var extensions: [ExtensionDeclaration] = []

        var isEmpty: Bool {
            constructs.isEmpty
                && enumerations.isEmpty
                && macros.isEmpty
                && extensions.isEmpty
        }

        mutating func merge(_ other: EmittedDeclarationBundle) {
            constructs.append(contentsOf: other.constructs)
            enumerations.append(contentsOf: other.enumerations)
            macros.append(contentsOf: other.macros)
            extensions.append(contentsOf: other.extensions)
        }
    }

    static func expand(
        sourceFile: ModuleFileNode,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> ModuleFileNode {
        let module = sourceFile
        let emittedDeclarationBundles =
            try module.enumerations.map {
                try emittedDeclarations(from: $0, macros: macros, context: context)
            }
        let expandedExtensions = try module.extensions.map {
            try expand(extensionDeclaration: $0, macros: macros, context: context)
        }
        let expandedBlockMacros = try module.blockMacros.map {
            try expand(
                blockMacro: $0,
                macros: macros,
                context: context
            )
        }
        return ModuleFileNode(
            blockMacros: expandedBlockMacros,
            constructs: try module.constructs.map {
                try expand(
                    construct: $0,
                    macros: macros,
                    context: context
                )
            } + emittedDeclarationBundles.flatMap(\.constructs),
            enumerations: module.enumerations
                + emittedDeclarationBundles.flatMap(\.enumerations),
            macros: module.macros
                + emittedDeclarationBundles.flatMap(\.macros),
            extensions: expandedExtensions
                + emittedDeclarationBundles.flatMap(\.extensions)
        )
    }

    static func expand(
        blockMacro: BlockMacroNode,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> BlockMacroNode {
        let isLLVMArtifactBlock = hasLLVMBlockMarker(blockMacro.macros, macros: macros)
            && canLowerLLVMArtifactBlock(
                blockMacro.body,
                macros: macros,
                context: context
            )
        let expandedBody =
            isLLVMArtifactBlock
            ? blockMacro.body
            : try expand(
                statements: blockMacro.body,
                expectedReturnType: nil,
                macros: macros,
                context: context
            )
        let memberText =
            isLLVMArtifactBlock
            ? ""
            : evaluatedStringMacroStatements(
                in: blockMacro.body,
                macros: macros,
                context: context
            ).joined(separator: "\n")
        let rawBody = memberText.isEmpty ? blockMacro.rawBody : memberText
        let preEvaluatedApplications = blockMacro.macros.map {
            guard $0.name != "construct" else {
                return $0
            }
            return attachingEvaluatedStringValue(
                to: $0,
                rawBody: rawBody,
                bodyStatements: isLLVMArtifactBlock ? blockMacro.body : nil,
                macros: macros,
                context: context
            )
        }
        let attachmentRecords = preEvaluatedApplications.compactMap { application in
            guard application.name != "construct" else {
                return nil
            }
            return application.evaluatedStringValue
        }.filter { !$0.isEmpty }.joined(separator: "\n")
        let constructRawBody =
            attachmentRecords.isEmpty
            ? rawBody
            : rawBody.isEmpty ? attachmentRecords : attachmentRecords + "\n" + rawBody
        let applications = preEvaluatedApplications.map {
            attachingEvaluatedStringValue(
                to: $0,
                rawBody: $0.name == "construct" ? constructRawBody : rawBody,
                bodyStatements: isLLVMArtifactBlock ? blockMacro.body : nil,
                macros: macros,
                context: context
            )
        }
        return BlockMacroNode(macros: applications, body: expandedBody, rawBody: rawBody)
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
                    syntaxResolver: context.syntaxResolver)
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
        let statementValues = statements.map(statementValue)
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

    static func blockMacroTargetValue(
        rawBody: String,
        application: MacroApplication
    ) -> CompileTimeValue {
        .object(
            typeName: "Block",
            fields: [
                "application": MacroTargetValueBuilder().value(for: application),
                "declaration": .object(
                    typeName: "Block.Declaration",
                    fields: [
                        "body": .array([]),
                        "statements": .array([]),
                    ]
                ),
                "body": .array([]),
                "statements": .array([]),
                "rawBody": .string(rawBody),
                "rawBodyText": .string(rawBody),
            ]
        )
    }

    private static func statementValue(_ statement: Statement) -> CompileTimeValue {
        switch statement {
        case .emitted(let text):
            return .object(
                typeName: "EmittedStatement",
                fields: [
                    "written": .string(text),
                    "text": .string(text),
                ]
            )
        case .macroApplication, .macroInvocation:
            return .string(renderStatementForBlockValue(statement))
        }
    }

    private static func expressionValue(_ expression: Expression) -> CompileTimeValue {
        switch expression {
        case .integer(let value):
            return .object(typeName: "IntegerLiteralExpression", fields: ["value": .integer(value)])
        case .double(let value):
            return .object(typeName: "DoubleLiteralExpression", fields: ["value": .double(value)])
        case .string(let value):
            return .object(typeName: "StringLiteralExpression", fields: ["value": .string(value)])
        case .boolean(let value):
            return .object(typeName: "BooleanLiteralExpression", fields: ["value": .boolean(value)])
        case .identifier(let name):
            return .object(typeName: "IdentifierExpression", fields: ["name": .string(name)])
        case .call(let name, let arguments):
            return .object(
                typeName: "CallExpression",
                fields: [
                    "name": .string(name),
                    "arguments": .array(arguments.map(callArgumentValue)),
                ]
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .object(
                typeName: "BinaryExpression",
                fields: [
                    "lhs": expressionValue(lhs),
                    "operator": .string(operatorSymbol.rawValue),
                    "rhs": expressionValue(rhs),
                ]
            )
        default:
            return .object(
                typeName: "WrittenExpression",
                fields: [
                    "text": .string(renderExpressionForStringify(expression))
                ]
            )
        }
    }

    private static func callArgumentValue(_ argument: CallArgument) -> CompileTimeValue {
        .object(
            typeName: "CallArgument",
            fields: [
                "label": argument.label.map { .string($0) } ?? .nilValue,
                "value": expressionValue(argument.value),
            ]
        )
    }

    static func renderStatementForBlockValue(_ statement: Statement) -> String {
        switch statement {
        case .emitted(let text):
            return text
        case .macroApplication(let name, let arguments):
            let renderedArguments = renderArgumentsForStringify(arguments)
            if renderedArguments.isEmpty {
                return "@\(name)"
            }
            return "@\(name)(\(renderedArguments))"
        case .macroInvocation(let name, let argumentClause, let body):
            return renderStatementMacroInvocation(
                name: name,
                argumentClause: argumentClause,
                body: renderStatementsForRawBody(body)
            )
        }
    }

    static func expand(
        extensionDeclaration: ExtensionDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> ExtensionDeclaration {
        return extensionDeclaration
    }

    // Evaluates a construct-attached macro and, when it returns a string,
    // carries that processed result on the application so Range-authored
    // construct macros can consume sibling attachment records.
    static func attachingEvaluatedStringValue(
        to application: MacroApplication,
        construct: ConstructDeclaration,
        context: MacroExpansionContext
    ) -> MacroApplication {
        let targetValueBuilder = MacroTargetValueBuilder(
            macroDeclarationsByName: context.macroDeclarationsByName,
            macroMetadataByName: context.macroMetadataByName,
            constructsByName: context.graphContext.constructsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            extensionsByTargetName: context.graphContext.extensionsByTargetName
        )
        let targetValue = targetValueBuilder.targetValue(for: construct)

        if let metadata = context.macroMetadataByName[application.name],
            !metadata.valueType.isMacroMetadataEffect,
            metadata.valueType == .named("String"),
            let value = try? MacroTargetValueBuilder.evaluateMacroMetadataValue(
                for: application,
                metadata: metadata,
                targetValue: targetValue,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
                context: context
            ),
            case .string(let processed) = value
        {
            var updated = application
            updated.evaluatedStringValue = processed
            return updated
        }

        guard let macro = context.macroDeclarationsByName[application.name],
            macro.expansionType == .named("String"),
            let argumentBindings = try? parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )
        else {
            return application
        }
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: targetValue,
            graphBinding: "graph",
            selfValue: targetValueBuilder.value(for: macro),
            localBindings: argumentBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context
        )
        var locals = argumentBindings
        guard case .string(let processed)? = evaluator.evaluateStatements(macro.body, locals: &locals)
        else {
            return application
        }
        var updated = application
        updated.evaluatedStringValue = processed
        return updated
    }

    static func attachingEvaluatedStringValues(
        to applications: [MacroApplication],
        body: [Statement],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> [MacroApplication] {
        applications.map { application in
            guard let macro = macros[application.name],
                macro.expansionType == .named("String")
            else {
                return application
            }

            let targetValue = blockMacroTargetValue(body)
            let evaluator = CompileTimeValueEvaluator(
                targetBinding: "target",
                targetValue: targetValue,
                graphBinding: "graph",
                selfValue: MacroTargetValueBuilder(
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    macroMetadataByName: context.macroMetadataByName,
                    knownObjectTypeNames: context.graphContext.knownObjectTypeNames
                ).value(for: macro),
                localBindings: [:],
                macroDeclarationsByName: context.macroDeclarationsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
                context: context
            )

            var localBindings: [String: Expression] = [:]
            guard case .string(let processed)? = evaluator.evaluateStatements(
                macro.body,
                locals: &localBindings
            ) else {
                return application
            }

            var updated = application
            updated.evaluatedStringValue = processed
            return updated
        }

    }

    static func attachingEvaluatedStringValue(
        to application: MacroApplication,
        rawBody: String,
        bodyStatements: [Statement]? = nil,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> MacroApplication {
        let applicationWithBody = MacroApplication(
            name: application.name,
            genericArguments: application.genericArguments,
            argumentClause: application.argumentClause,
            rawBodyLanguage: application.rawBodyLanguage,
            rawBody: rawBody,
            evaluatedStringValue: application.evaluatedStringValue
        )
        if let bodyStatements,
            let artifact = evaluatedBlockLLVMArtifact(
                application: applicationWithBody,
                statements: bodyStatements,
                macros: macros,
                context: context
            )
        {
            var updated = applicationWithBody
            updated.evaluatedStringValue = artifact
            return updated
        }
        guard let macro = macros[application.name] else { return applicationWithBody }
        let targetValue = blockMacroTargetValue(rawBody: rawBody, application: applicationWithBody)
        guard
            let argumentBindings = (try? parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )) ?? singlePositionalMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )
        else {
            return applicationWithBody
        }
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: targetValue,
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: argumentBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context
        )

        var locals = argumentBindings
        guard case .string(let processed)? = evaluator.evaluateStatements(macro.body, locals: &locals)
        else {
            return applicationWithBody
        }

        var updated = applicationWithBody
        updated.evaluatedStringValue = processed
        return updated
    }

    private static func evaluatedBlockLLVMArtifact(
        application: MacroApplication,
        statements: [Statement],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> String? {
        guard !statements.isEmpty,
            let macro = macros[application.name]
        else {
            return nil
        }

        var bodyLines: [String] = []
        var sawReturn = false
        let llvmContext = CompileTimeLLVMContext()

        for statement in statements {
            switch statement {
            case .macroApplication:
                guard
                    let effect = evaluatedLLVMBlockStatementEffect(
                        statement,
                        llvmContext: llvmContext,
                        macros: macros,
                        context: context
                    )
                else {
                    return nil
                }
                if let binding = effect.binding, let type = effect.type {
                    llvmContext.bindings[binding] = type
                    llvmContext.bindingConstructs[binding] = effect.construct ?? ""
                    llvmContext.bindingReturnCasts[binding] = effect.returnCast ?? ""
                }
                bodyLines.append(contentsOf: effect.lines)
                if effect.kind == "llvm-terminator" {
                    sawReturn = true
                }
            default:
                return nil
            }
        }

        guard sawReturn else {
            return nil
        }

        return evaluatedBlockArtifactMacro(
            macro: macro,
            application: application,
            body: bodyLines.joined(separator: "\n"),
            context: context
        )
    }

    private static func hasLLVMBlockMarker(
        _ applications: [MacroApplication],
        macros: [String: MacroDeclaration]
    ) -> Bool {
        applications.contains { application in
            hasLLVMBlockMarker(application)
                || macros[application.name].map { hasLLVMBlockMarker($0.macros) } == true
        }
    }

    private static func hasLLVMBlockMarker(_ applications: [MacroApplication]) -> Bool {
        applications.contains(where: hasLLVMBlockMarker)
    }

    private static func hasLLVMBlockMarker(_ application: MacroApplication) -> Bool {
            guard application.name == "block",
                let argumentClause = application.argumentClause,
                let arguments = try? parsedMacroArguments(argumentClause: argumentClause)
            else {
                return false
            }
            let kindExpression = argument(named: "kind", in: arguments) ?? arguments.first?.value
            return minimalStringValue(kindExpression) == "llvm"
    }

    private static func canLowerLLVMArtifactBlock(
        _ statements: [Statement],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> Bool {
        guard !statements.isEmpty else {
            return false
        }
        var sawReturn = false
        let llvmContext = CompileTimeLLVMContext()
        for statement in statements {
            guard case .macroApplication = statement,
                let effect = evaluatedLLVMBlockStatementEffect(
                    statement,
                    llvmContext: llvmContext,
                    macros: macros,
                    context: context
                )
            else {
                return false
            }
            if let binding = effect.binding, let type = effect.type {
                llvmContext.bindings[binding] = type
                llvmContext.bindingConstructs[binding] = effect.construct ?? ""
                llvmContext.bindingReturnCasts[binding] = effect.returnCast ?? ""
            }
            if effect.kind == "llvm-terminator" {
                sawReturn = true
            }
        }
        return sawReturn
    }

    private struct LLVMBlockStatementEffect {
        var kind: String
        var lines: [String]
        var binding: String?
        var type: String?
        var construct: String?
        var returnCast: String?
    }

    private static func evaluatedLLVMBlockStatementEffect(
        _ statement: Statement,
        llvmContext: CompileTimeLLVMContext,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> LLVMBlockStatementEffect? {
        guard case .macroApplication(let name, let arguments) = statement,
            let macro = macros[name],
            let localBindings = preparedLLVMBlockStatementBindings(
                macro: macro,
                arguments: arguments,
                llvmContext: llvmContext,
                macros: macros,
                context: context
            )
        else {
            return nil
        }

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: .object(typeName: "LLVMStatementTarget", fields: [:]),
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context,
            llvmContext: llvmContext
        )
        var locals = localBindings
        guard case .string(let effect)? = evaluator.evaluateStatements(macro.body, locals: &locals) else {
            return nil
        }
        return llvmBlockStatementEffect(effect)
    }

    private static func preparedLLVMBlockStatementBindings(
        macro: MacroDeclaration,
        arguments: [CallArgument],
        llvmContext: CompileTimeLLVMContext,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> [String: Expression]? {
        let argumentBindings = (try? parseMacroArgumentBindings(for: macro, arguments: arguments)) ?? [:]
        let (localBindings, preparedValues) = preparedLLVMArgumentBindings(
            argumentBindings,
            llvmContext: llvmContext,
            macros: macros,
            context: context
        )

        let requiredValueNames = requiredLLVMValueParameterNames(for: macro)
        guard requiredValueNames.allSatisfy({ preparedValues[$0] != nil }) else {
            return nil
        }

        return localBindings
    }

    private static func requiredLLVMValueParameterNames(for macro: MacroDeclaration) -> Set<String> {
        Set(macro.parameters.compactMap { parameter in
            parameter.localName == "value" ? parameter.localName : nil
        })
    }

    private static func preparedLLVMValue(
        _ expression: Expression?,
        llvmContext: CompileTimeLLVMContext,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> MinimalLLVMValue? {
        minimalLLVMValue(
            expression,
            llvmContext: llvmContext,
            macros: macros,
            context: context
        )
    }

    private static func preparedLLVMArgumentBindings(
        _ argumentBindings: [String: Expression],
        llvmContext: CompileTimeLLVMContext,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> ([String: Expression], [String: MinimalLLVMValue]) {
        var localBindings = argumentBindings
        var values: [String: MinimalLLVMValue] = [:]
        for (name, expression) in argumentBindings {
            guard let value = preparedLLVMValue(
                expression,
                llvmContext: llvmContext,
                macros: macros,
                context: context
            ) else {
                continue
            }
            values[name] = value
            localBindings[name] = .string(value.payload)
        }
        return (localBindings, values)
    }

    private static func llvmBlockStatementEffect(_ effect: String) -> LLVMBlockStatementEffect? {
        let prefix: String
        if effect.hasPrefix("llvm-effect|kind=") {
            prefix = "llvm-effect|kind="
        } else if effect.hasPrefix("effect|kind=") {
            prefix = "effect|kind="
        } else {
            return nil
        }
        let remainder = effect.dropFirst(prefix.count)
        guard let bodySeparator = remainder.range(of: "|body=") else {
            return nil
        }
        let metadata = String(remainder[..<bodySeparator.lowerBound])
        let body = String(remainder[bodySeparator.upperBound...])
        let parts = metadata.split(separator: "|", omittingEmptySubsequences: false)
        guard let kind = parts.first.map(String.init),
            kind.hasPrefix("llvm-")
        else {
            return nil
        }

        var fields: [String: String] = [:]
        var binding: String?
        var type: String?
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                continue
            }
            fields[String(pair[0])] = String(pair[1])
        }
        binding = fields["binding"] ?? fields["name"]
        type = fields["type"]
        let construct = fields["construct"]
        let returnCast = fields["returnCast"]

        return LLVMBlockStatementEffect(
            kind: kind,
            lines: body.isEmpty ? [] : body.components(separatedBy: "\n"),
            binding: binding,
            type: type,
            construct: construct,
            returnCast: returnCast
        )
    }

    private static func evaluatedBlockArtifactMacro(
        macro: MacroDeclaration,
        application: MacroApplication,
        body: String,
        context: MacroExpansionContext
    ) -> String? {
        let argumentBindings =
            ((try? parseMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )) ?? singlePositionalMacroArgumentBindings(
                for: macro,
                argumentClause: application.argumentClause
            )) ?? [:]
        var localBindings = argumentBindings
        localBindings["body"] = .string(body)
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: .object(typeName: "LLVMArtifactTarget", fields: [:]),
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context
        )
        var locals = localBindings
        guard case .string(let llvm)? = evaluator.evaluateStatements(macro.body, locals: &locals) else {
            return nil
        }
        return llvm
    }

    private struct MinimalLLVMValue {
        var lines: [String]
        var type: String
        var operand: String
        var isImmediate: Bool
        var payload: String
    }

    private static func minimalLLVMValue(
        _ expression: Expression?,
        llvmContext: CompileTimeLLVMContext,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> MinimalLLVMValue? {
        evaluatedLLVMValue(
            expression,
            llvmContext: llvmContext,
            macros: macros,
            context: context
        )
    }

    private static func evaluatedLLVMValue(
        _ expression: Expression?,
        llvmContext: CompileTimeLLVMContext,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> MinimalLLVMValue? {
        guard
            case .macroInvocation(let name, let arguments)? = expression,
            let macro = macros[name]
        else {
            return nil
        }

        let argumentBindings: [String: Expression]
        do {
            argumentBindings = try parseMacroArgumentBindings(for: macro, arguments: arguments)
        } catch {
            return nil
        }

        let (localBindings, _) = preparedLLVMArgumentBindings(
            argumentBindings,
            llvmContext: llvmContext,
            macros: macros,
            context: context
        )

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: .object(typeName: "LLVMValueTarget", fields: [:]),
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context,
            llvmContext: llvmContext
        )
        var locals = localBindings
        guard case .string(let payload)? = evaluator.evaluateStatements(macro.body, locals: &locals) else {
            return nil
        }
        return minimalLLVMValuePayload(payload)
    }

    private static func minimalLLVMValuePayload(_ payload: String) -> MinimalLLVMValue? {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.first == "value" || parts.first == "llvm-value" else {
            return nil
        }

        var fields: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                continue
            }
            fields[String(pair[0])] = String(pair[1])
        }

        guard
            let type = fields["llvm.type"] ?? fields["type"],
            isValidLLVMType(type),
            let operand = fields["llvm.operand"] ?? fields["operand"],
            isValidImmediateOperand(operand)
        else {
            return nil
        }

        let instructions = fields["llvm.instructions"]
            ?? fields["instructions"]
            ?? fields["llvm.prelude"]
            ?? fields["prelude"]
            ?? ""
        let lines = instructions.isEmpty ? [] : instructions.components(separatedBy: "\n")
        return MinimalLLVMValue(
            lines: lines,
            type: type,
            operand: operand,
            isImmediate: lines.isEmpty && !operand.hasPrefix("%"),
            payload: payload
        )
    }

    private static func argument(named name: String, in arguments: [CallArgument]) -> Expression? {
        arguments.first(where: { $0.label == name })?.value
    }

    private static func minimalStringValue(_ expression: Expression?) -> String? {
        guard let expression else {
            return nil
        }
        switch expression {
        case .string(let value):
            return value
        case .macroInvocation(let name, let arguments) where name == "string":
            let valueExpression = argument(named: "value", in: arguments) ?? arguments.first?.value
            guard let valueExpression else {
                return ""
            }
            return minimalStringValue(valueExpression)
        default:
            return nil
        }
    }

    private static func isValidLLVMIdentifier(_ name: String) -> Bool {
        guard let first = name.first,
            first.isLetter || first == "_"
        else {
            return false
        }
        return name.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_"
        }
    }

    private static func isValidLLVMType(_ type: String) -> Bool {
        if type == "float" || type == "double" {
            return true
        }
        guard type.first == "i" else {
            return false
        }
        return type.dropFirst().allSatisfy(\.isNumber)
    }

    private static func isValidImmediateOperand(_ operand: String) -> Bool {
        guard !operand.isEmpty else {
            return false
        }
        if operand.first == "%" {
            return operand.dropFirst().allSatisfy { character in
                character.isLetter || character.isNumber || character == "_" || character == "."
            }
        }
        return operand.allSatisfy { $0.isNumber || $0 == "-" || $0 == "." }
    }

    static func evaluatedStringMacroStatements(
        in statements: [Statement],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) -> [String] {
        statements.enumerated().compactMap { offset, statement -> String? in
            let name: String
            let argumentBindings: [String: Expression]?
            let targetValue: CompileTimeValue
            switch statement {
            case .macroApplication(let macroName, let arguments):
                name = macroName
                if let macro = macros[name] {
                    argumentBindings = try? parseMacroArgumentBindings(
                        for: macro,
                        arguments: arguments
                    )
                } else {
                    return nil
                }
                targetValue = memberMacroTargetValue(ordinal: offset)
            case .macroInvocation(let macroName, let argumentClause, let body):
                name = macroName
                if let macro = macros[name] {
                    argumentBindings = (try? parseMacroArgumentBindings(
                        for: macro,
                        argumentClause: argumentClause
                    )) ?? singlePositionalMacroArgumentBindings(
                        for: macro,
                        argumentClause: argumentClause
                    )
                } else {
                    return nil
                }
                targetValue = memberMacroTargetValue(
                    ordinal: offset,
                    bodyText: evaluatedStringMacroStatements(
                        in: body,
                        macros: macros,
                        context: context
                    ).joined(separator: "\n")
                )
            default:
                return nil
            }
            guard let macro = macros[name] else {
                return nil
            }
            guard let argumentBindings else {
                return nil
            }
            let evaluator = CompileTimeValueEvaluator(
                targetBinding: "target",
                targetValue: targetValue,
                graphBinding: "graph",
                selfValue: MacroTargetValueBuilder(
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    macroMetadataByName: context.macroMetadataByName,
                    constructsByName: context.graphContext.constructsByName,
                    knownObjectTypeNames: context.graphContext.knownObjectTypeNames
                ).value(for: macro),
                localBindings: argumentBindings,
                macroDeclarationsByName: context.macroDeclarationsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
                context: context
            )
            var locals = argumentBindings
            guard case .string(let processed)? = evaluator.evaluateStatements(
                macro.body,
                locals: &locals
            ) else {
                return nil
            }
            return processed
        }
    }

    static func memberMacroTargetValue(ordinal: Int, bodyText: String = "") -> CompileTimeValue {
        .object(
            typeName: "MemberMacro.Target",
            fields: [
                "index": .integer(ordinal),
                "ordinal": .integer(ordinal),
                "declaration": .object(
                    typeName: "MemberMacro.Declaration",
                    fields: [
                        "bodyText": .string(bodyText),
                        "text": .string(bodyText),
                    ]
                ),
                "bodyText": .string(bodyText),
                "text": .string(bodyText),
            ]
        )
    }

    static func evaluatedStringStatementMacro(
        name: String,
        argumentClause: String?,
        body: [Statement],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> String {
        guard let macro = macros[name] else {
            return renderStatementMacroInvocation(
                name: name,
                argumentClause: argumentClause,
                body: renderStatementsForRawBody(body)
            )
        }
        let application = MacroApplication(
            name: name,
            genericArguments: [],
            argumentClause: argumentClause
        )
        guard
            let argumentBindings = (try? parseMacroArgumentBindings(
                for: macro,
                argumentClause: argumentClause
            )) ?? singlePositionalMacroArgumentBindings(
                for: macro,
                argumentClause: argumentClause
            )
        else {
            throw ParseError("Could not bind arguments for statement macro @\(name).")
        }

        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: statementMacroTargetValue(body: body, application: application),
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: argumentBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context
        )
        var locals = argumentBindings
        guard case .string(let processed)? = evaluator.evaluateStatements(macro.body, locals: &locals)
        else {
            throw ParseError("Could not evaluate statement macro @\(name) to String.")
        }
        return processed
    }

    static func evaluatedStringStatementMacro(
        name: String,
        arguments: [CallArgument],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> String {
        let statement = Statement.macroApplication(name: name, arguments: arguments)
        guard let macro = macros[name],
            let argumentBindings = try? parseMacroArgumentBindings(
                for: macro,
                arguments: arguments
            )
        else {
            return renderStatementForBlockValue(statement)
        }

        let application = MacroApplication(
            name: name,
            genericArguments: [],
            argumentClause: renderArgumentsForStringify(arguments)
        )
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: "target",
            targetValue: statementMacroTargetValue(body: [], application: application),
            graphBinding: "graph",
            selfValue: MacroTargetValueBuilder(
                macroDeclarationsByName: context.macroDeclarationsByName,
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
                knownObjectTypeNames: context.graphContext.knownObjectTypeNames
            ).value(for: macro),
            localBindings: argumentBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            callableDeclarationsByName: context.callableDeclarationsByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames,
            context: context
        )
        var locals = argumentBindings
        guard case .string(let processed)? = evaluator.evaluateStatements(macro.body, locals: &locals)
        else {
            throw ParseError("Could not evaluate statement macro @\(name) to String.")
        }
        return processed
    }

    private static func macroTargetsStatementSurface(_ macro: MacroDeclaration) -> Bool {
        if macro.macros.contains(where: { $0.name == "statement" }) {
            return true
        }
        return macro.target.map(macroTargetIncludesStatementSurface) ?? false
    }

    private static func macroTargetIncludesStatementSurface(_ target: MacroTarget) -> Bool {
        switch target {
        case .macroSurface(let name):
            return name == "statement"
        case .anyOf(let targets), .allOf(let targets):
            return targets.contains(where: macroTargetIncludesStatementSurface)
        case .syntax:
            return false
        }
    }

    static func statementMacroTargetValue(
        body: [Statement],
        application: MacroApplication
    ) -> CompileTimeValue {
        let statementValues = body.map(statementValue)
        let bodyText = renderStatementsForRawBody(body)
        return .object(
            typeName: "Block",
            fields: [
                "index": .integer(0),
                "ordinal": .integer(0),
                "application": MacroTargetValueBuilder().value(for: application),
                "declaration": .object(
                    typeName: "Block.Declaration",
                    fields: [
                        "index": .integer(0),
                        "ordinal": .integer(0),
                        "body": .array(statementValues),
                        "statements": .array(statementValues),
                        "bodyText": .string(bodyText),
                        "text": .string(bodyText),
                    ]
                ),
                "body": .array(statementValues),
                "statements": .array(statementValues),
                "bodyText": .string(bodyText),
                "text": .string(bodyText),
            ]
        )
    }

    static func singlePositionalMacroArgumentBindings(
        for macro: MacroDeclaration,
        argumentClause: String?
    ) -> [String: Expression]? {
        guard macro.parameters.count == 1,
            let parameter = macro.parameters.first,
            let argumentClause,
            let arguments = try? parsedMacroArguments(argumentClause: argumentClause),
            arguments.count == 1,
            arguments[0].label == nil
        else {
            return nil
        }

        return [parameter.localName: arguments[0].value]
    }

    static func renderStatementsForRawBody(_ statements: [Statement]) -> String {
        statements.map(renderStatementForBlockValue).joined(separator: "\n")
    }

    static func renderStatementMacroInvocation(
        name: String,
        argumentClause: String?,
        body: String
    ) -> String {
        let arguments = argumentClause.map { "(\($0))" } ?? ""
        guard !body.isEmpty else {
            return "@\(name)\(arguments)"
        }
        return "@\(name)\(arguments) {\n\(body)\n}"
    }

    static func stringyArgumentFields(argumentClause: String?) -> [String] {
        guard let argumentClause, !argumentClause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let arguments = try? parsedMacroArguments(argumentClause: argumentClause)
        else {
            return []
        }
        return arguments.compactMap { argument in
            guard let label = argument.label else {
                return nil
            }
            return "\(label)=\(stringyArgumentValue(argument.value))"
        }
    }

    static func parsedMacroArguments(argumentClause: String) throws -> [CallArgument] {
        var parser = try Parser(source: "macro(\(argumentClause))")
        _ = try parser.consumeCallableName()
        let arguments = try parser.parseInvocationArgumentsIfPresent()
        try parser.consume(Token.eof)
        return arguments
    }

    static func stringyArgumentValue(_ expression: Expression) -> String {
        switch expression {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .identifier(let name):
            return name
        case .call(let name, let arguments):
            let renderedArguments = arguments.map { argument in
                if let label = argument.label {
                    return "\(label): \(stringyArgumentValue(argument.value))"
                }
                return stringyArgumentValue(argument.value)
            }.joined(separator: ", ")
            return "\(name)(\(renderedArguments))"
        default:
            return MacroExpander.renderExpressionForStringify(expression)
        }
    }

    static func expand(
        construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> ConstructDeclaration {
        let preEvaluatedMacros = construct.macros.map { application in
            guard application.name != "construct" else {
                return application
            }
            return attachingEvaluatedStringValue(
                to: application,
                construct: construct,
                context: context
            )
        }
        let constructForConstructMacroEvaluation = ConstructDeclaration(
            macros: preEvaluatedMacros,
            kind: construct.kind,
            attribute: construct.attribute,
            name: construct.name,
            genericParameters: construct.genericParameters,
            conformances: construct.conformances,
            states: construct.states,
            bindings: construct.bindings,
            deriveds: construct.deriveds,
            values: construct.values,
            initializers: construct.initializers,
            callables: construct.callables,
            constructs: construct.constructs
        )
        let macrosWithValues = preEvaluatedMacros.map { application in
            attachingEvaluatedStringValue(
                to: application,
                construct: application.name == "construct"
                    ? constructForConstructMacroEvaluation
                    : construct,
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
                    context: context
                )
            },
            bindings: try construct.bindings.map {
                try expand(
                    binding: $0,
                    macros: macros,
                    context: context
                )
            },
            deriveds: try construct.deriveds.map {
                try expand(
                    derived: $0,
                    macros: macros,
                    context: context
                )
            },
            values: try construct.values.map {
                try expand(
                    value: $0,
                    macros: macros,
                    context: context
                )
            },
            initializers: try construct.initializers.map {
                try expand(
                    initializer: $0,
                    macros: macros,
                    context: context
                )
            },
            callables: try construct.callables.map {
                try expand(
                    callable: $0,
                    macros: macros,
                    context: context
                )
            },
            constructs: try construct.constructs.map {
                try expand(
                    construct: $0,
                    macros: macros,
                    context: context
                )
            }
        )
    }

    static func expand(
        callable: CallableDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext,
        preserveStatementMacroApplications: Bool = false
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
                    context: context,
                    preserveStatementMacroApplications: preserveStatementMacroApplications
                )
            }
        )
    }

    static func expand(
        initializer: InitializerDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
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
                    context: context
                )
            }
        )
    }

    static func expand(
        derived: DerivedDeclaration,
        macros: [String: MacroDeclaration],
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
                    context: context
                )
            }
        )
    }

    static func expand(
        state: StateDeclaration,
        macros: [String: MacroDeclaration],
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
        value declaration: ValueDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> ValueDeclaration {
        let type = try parsePropertyTypeReference(from: declaration.typeName)

        return ValueDeclaration(
            macros: declaration.macros,
            name: declaration.name,
            typeName: declaration.typeName,
            value: try declaration.value.map {
                try expand(
                    expression: $0,
                    expectedType: type,
                    macros: macros,
                    context: context
                )
            }
        )
    }

    static func expand(
        binding declaration: BindingDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
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
                    context: context
                ),
                set: try expand(
                    statements: setterBody,
                    expectedReturnType: nil,
                    macros: macros,
                    context: context
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

    static func parsePropertyTypeReference(from raw: String) throws -> TypeReference {
        var parser = try Parser(source: raw)
        let type = try parser.parseTypeReferenceNode()
        try parser.consume(.eof)
        return type
    }

    static func expand(
        statements: [Statement],
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext,
        preserveStatementMacroApplications: Bool = false
    ) throws -> [Statement] {
        var expanded: [Statement] = []
        for statement in statements {
            expanded.append(
                contentsOf: try expand(
                    statement: statement,
                    expectedReturnType: expectedReturnType,
                    macros: macros,
                    context: context,
                    preserveStatementMacroApplications: preserveStatementMacroApplications
                ))
        }
        return expanded
    }

    static func expand(
        statement: Statement,
        expectedReturnType: TypeReference? = nil,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext,
        preserveStatementMacroApplications: Bool = false
    ) throws -> [Statement] {
        switch statement {
        case .macroInvocation(let name, let argumentClause, let body):
            if preserveStatementMacroApplications,
                macros[name].map(macroTargetsStatementSurface) == true
            {
                return [statement]
            }
            let expandedBody = try expand(
                statements: body,
                expectedReturnType: nil,
                macros: macros,
                context: context,
                preserveStatementMacroApplications: preserveStatementMacroApplications
            )
            return [
                .emitted(
                    try evaluatedStringStatementMacro(
                        name: name,
                        argumentClause: argumentClause,
                        body: expandedBody,
                        macros: macros,
                        context: context
                    )
                )
            ]
        case .macroApplication(let name, let arguments):
            if preserveStatementMacroApplications,
                macros[name].map(macroTargetsStatementSurface) == true
            {
                return [statement]
            }
            if macros[name].map(macroTargetsStatementSurface) == true {
                return [
                    .emitted(
                        try evaluatedStringStatementMacro(
                            name: name,
                            arguments: arguments,
                            macros: macros,
                            context: context
                        )
                    )
                ]
            }
            return [statement]
        default:
            return [statement]
        }
    }

    static func expand(
        parameters: [RangeFunctionParameter],
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> [RangeFunctionParameter] {
        parameters.map { parameter in
            let attachedParameterMacros: [MacroDeclaration] = parameter.macros.compactMap {
                macroApplication in
                guard let macro = macros[macroApplication.name],
                    macroTargetAllows(
                        macro.target!, kind: .parameter,
                        syntaxResolver: context.syntaxResolver)
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

            return RangeFunctionParameter(
                macros: parameter.macros,
                name: parameter.localName,
                typeReference: typeReference,
                defaultValue: parameter.defaultValue,
                valueCapability: parameter.valueCapability,
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
                        context: context
                    )
                )
            }

            return .call(name: name, arguments: rewrittenArguments)
        case .macroInvocation(let name, let arguments):
            guard let macro = macros[name],
                let target = macro.target,
                macroTargetAllows(
                    target, kind: .expression,
                    syntaxResolver: context.syntaxResolver)
            else {
                let rewrittenArguments = try arguments.map { argument in
                    CallArgument(
                        label: argument.label,
                        value: try expand(
                            expression: argument.value,
                            expectedType: nil,
                            macros: macros,
                            context: context
                        )
                    )
                }
                return .macroInvocation(name: name, arguments: rewrittenArguments)
            }

            let rewrittenArguments = try arguments.map { argument in
                CallArgument(
                    label: argument.label,
                    value: try expand(
                        expression: argument.value,
                        expectedType: nil,
                        macros: macros,
                        context: context
                    )
                )
            }
            return .macroInvocation(name: name, arguments: rewrittenArguments)
        case .array(let elements):
            return .array(
                try elements.map {
                    try expand(
                        expression: $0,
                        expectedType: nil,
                        macros: macros,
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
                            context: context
                        ),
                        value: try expand(
                            expression: element.value,
                            expectedType: nil,
                            macros: macros,
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
                    context: context),
                trueExpression: try expand(
                    expression: trueExpression,
                    expectedType: expectedType,
                    macros: macros,
                    context: context
                ),
                falseExpression: try expand(
                    expression: falseExpression,
                    expectedType: expectedType,
                    macros: macros,
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
                    context: context)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: try expand(
                    expression: lhs,
                    expectedType: nil,
                    macros: macros,
                    context: context),
                operatorSymbol: operatorSymbol,
                rhs: try expand(
                    expression: rhs,
                    expectedType: nil,
                    macros: macros,
                    context: context)
            )
        case .block(let body):
            return .block(
                try body.flatMap {
                    try expand(
                        statement: $0,
                        expectedReturnType: nil,
                        macros: macros,
                        context: context
                    )
                }
            )
        case .integer, .double, .string, .boolean, .nilLiteral:
            return expression
        case .identifier:
            return expression
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
                    syntaxResolver: context.syntaxResolver)
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
                nestedEmitted.enumerations.isEmpty
                    && nestedEmitted.extensions.isEmpty
            else {
                throw ParseError(
                    "Nested construct macros can currently emit peer constructs only in this bootstrap pass."
                )
            }
            emitted.constructs.append(contentsOf: nestedEmitted.constructs)
        }

        return emitted
    }

    static func replacementDeclarations(
        from construct: ConstructDeclaration,
        macros: [String: MacroDeclaration],
        context: MacroExpansionContext
    ) throws -> EmittedDeclarationBundle {
        var replacement = EmittedDeclarationBundle()

        for application in construct.macros {
            guard let macro = macros[application.name],
                macroTargetAllows(
                    macro.target!, kind: .construct,
                    syntaxResolver: context.syntaxResolver)
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
            replacement.merge(
                try replacementDeclarations(
                    from: macro,
                    construct: construct,
                    context: context,
                    argumentBindings: argumentBindings.merging(genericBindings) { _, generic in
                        generic
                    }
                )
            )
        }

        return replacement
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
                    syntaxResolver: context.syntaxResolver)
            else {
                continue
            }
            emitted.merge(
                try emittedDeclarations(
                    from: macro,
                    targetValue: MacroTargetValueBuilder(
                        macroMetadataByName: context.macroMetadataByName,
                        constructsByName: context.graphContext.constructsByName,
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
                constructsByName: context.graphContext.constructsByName,
                writtenSyntaxByID: context.graphContext.writtenSyntaxByID,
                extensionsByTargetName: context.graphContext.extensionsByTargetName
            ).targetValue(for: construct),
            context: context,
            argumentBindings: argumentBindings
        )
    }

    static func replacementDeclarations(
        from macro: MacroDeclaration,
        construct: ConstructDeclaration,
        context: MacroExpansionContext,
        argumentBindings: [String: Expression] = [:]
    ) throws -> EmittedDeclarationBundle {
        try replacementDeclarations(
            from: macro,
            targetValue: MacroTargetValueBuilder(
                macroMetadataByName: context.macroMetadataByName,
                constructsByName: context.graphContext.constructsByName,
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
        let body = substituteMacroBindings(in: macro.body, bindings: argumentBindings)
        try emitMacroDiagnostics(
            from: body,
            macro: macro,
            targetValue: targetValue,
            context: context
        )

        return EmittedDeclarationBundle()
    }

    static func replacementDeclarations(
        from macro: MacroDeclaration,
        targetValue: CompileTimeValue,
        context: MacroExpansionContext,
        argumentBindings: [String: Expression] = [:]
    ) throws -> EmittedDeclarationBundle {
        let body = substituteMacroBindings(in: macro.body, bindings: argumentBindings)
        try emitMacroDiagnostics(
            from: body,
            macro: macro,
            targetValue: targetValue,
            context: context
        )

        return EmittedDeclarationBundle()
    }

    static func emitMacroDiagnostics(
        from statements: [Statement],
        macro: MacroDeclaration,
        targetValue: CompileTimeValue? = nil,
        context: MacroExpansionContext,
        localBindings: [String: Expression] = [:]
    ) throws {
        try emitDiagnostics(
            from: statements,
            diagnosticOwnerName: macro.name,
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
        try emitDiagnostics(
            from: statements,
            diagnosticOwnerName: metadata.name,
            targetValue: targetValue,
            context: context,
            localBindings: localBindings
        )
    }

    private static func emitDiagnostics(
        from statements: [Statement],
        diagnosticOwnerName: String,
        targetValue: CompileTimeValue?,
        context: MacroExpansionContext,
        localBindings: [String: Expression] = [:]
    ) throws {
        let diagnostics = try macroDiagnostics(
            in: statements,
            diagnosticOwnerName: diagnosticOwnerName,
            diagnosticsBinding: "diagnostics",
            targetBinding: "target",
            targetValue: targetValue,
            graphBinding: "graph",
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
            case .macroApplication:
                let evaluator = CompileTimeValueEvaluator(
                    targetBinding: targetBinding,
                    targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                    graphBinding: graphBinding,
                    selfValue: macroSelfValue(named: diagnosticOwnerName),
                    localBindings: locals,
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    context: context
                )
                _ = evaluator.evaluateStatements([statement], locals: &locals)
            case .macroInvocation(let name, let argumentClause, let body):
                let evaluator = CompileTimeValueEvaluator(
                    targetBinding: targetBinding,
                    targetValue: targetValue ?? .object(typeName: "MacroDiagnostics", fields: [:]),
                    graphBinding: graphBinding,
                    selfValue: macroSelfValue(named: diagnosticOwnerName),
                    localBindings: locals,
                    macroDeclarationsByName: context.macroDeclarationsByName,
                    context: context
                )
                guard let control = evaluator.evaluateControlMacroEffect(
                    name: name,
                    argumentClause: argumentClause,
                    locals: locals
                ) else {
                    continue
                }

                switch control.kind {
                case "branch":
                    guard let condition = evaluator.controlConditionExpression(
                        control.condition,
                        locals: locals
                    ),
                        case .boolean(true) = evaluator.evaluate(condition, with: locals)
                    else {
                        continue
                    }
                    let branchResult = try macroDiagnosticsAndLocals(
                        in: body,
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
                case "loop":
                    guard let condition = evaluator.controlConditionExpression(
                        control.condition,
                        locals: locals
                    ) else {
                        continue
                    }
                    var iterationCount = 0
                    while case .boolean(true) = evaluator.evaluate(condition, with: locals) {
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
                default:
                    continue
                }
            default:
                continue
            }
        }

        return (diagnostics, locals)
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
        callerLLVMContext: CompileTimeLLVMContext? = nil,
        context: MacroExpansionContext
    ) throws -> CompileTimeValue? {
        guard macro.target == nil, macro.expansionType != nil else {
            return nil
        }

        var bindings = callerLocals
        let argumentBindings = try expressionMacroArgumentBindings(for: macro, arguments: arguments)
        for (name, expression) in argumentBindings {
            bindings[name] = resolvedSyntaxMacroArgument(
                expression,
                callerLocals: callerLocals,
                callerTargetBinding: callerTargetBinding,
                callerTargetValue: callerTargetValue,
                callerSelfValue: callerSelfValue,
                context: context
            )
        }

        return try evaluateFreestandingSyntaxMacroValueBody(
            macro,
            localBindings: bindings,
            callerTargetBinding: callerTargetBinding,
            callerTargetValue: callerTargetValue,
            callerSelfValue: callerSelfValue,
            callerLLVMContext: callerLLVMContext,
            context: context
        )
    }

    static func evaluateFreestandingSyntaxMacroValueBody(
        _ macro: MacroDeclaration,
        localBindings: [String: Expression],
        callerTargetBinding: String,
        callerTargetValue: CompileTimeValue,
        callerSelfValue: CompileTimeValue?,
        callerLLVMContext: CompileTimeLLVMContext? = nil,
        context: MacroExpansionContext
    ) throws -> CompileTimeValue? {
        let targetValue = callerTargetValue
        let selfValue = MacroTargetValueBuilder(
            macroDeclarationsByName: context.macroDeclarationsByName,
            macroMetadataByName: context.macroMetadataByName,
            knownObjectTypeNames: context.graphContext.knownObjectTypeNames
        ).value(for: macro)
        let evaluator = CompileTimeValueEvaluator(
            targetBinding: callerTargetBinding,
            targetValue: targetValue,
            graphBinding: "graph",
            selfValue: selfValue,
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            context: context,
            llvmContext: callerLLVMContext
        )
        var locals = localBindings
        return evaluator.evaluateStatements(macro.body, locals: &locals)
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

    static func renderAssignmentTarget(_ target: AssignmentTarget) -> String {
        switch target {
        case .state(let name), .binding(let name), .local(let name):
            return name
        case .member(let base, let name):
            return "\(renderAssignmentTarget(base)).\(name)"
        }
    }

    static func renderStatementRecordValue(
        _ expression: Expression,
        expectedType: TypeReference? = nil
    ) -> String {
        if let expectedType {
            switch (expectedType, expression) {
            case (.named("Int"), .integer), (.named("String"), .string),
                (.named("Bool"), .boolean), (.named("Float"), .double):
                return "\(expectedType.displayName)(\(renderExpressionForStringify(expression)))"
            case (.generic(.named("Int"), _), .integer):
                return "\(expectedType.displayName)(\(renderExpressionForStringify(expression)))"
            default:
                break
            }
        }
        return stringyArgumentValue(expression)
    }

}
