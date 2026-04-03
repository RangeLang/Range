import Foundation

extension Parser {
    mutating func parseCallableDeclaration() throws -> CallableDeclaration {
        if isBuilderCallableStart() {
            return try parseBuilderCallableDeclaration()
        }

        let macros = try parseMacroApplicationsIfPresent()
        var targetType: TypeReference?
        if case .identifier(let target) = peek(),
            peek(offset: 1) == .keyword(NeatSyntax.Keyword.function.rawValue)
        {
            targetType = .named(target)
            advance()
        }

        guard peek() == .keyword(NeatSyntax.Keyword.function.rawValue) else {
            throw ParseError("Expected callable declaration starting with function.")
        }
        advance()

        let name = try consumeCallableName()
        let genericParameters = try parseConstructGenericParameterClauseIfPresent()
        let hasExplicitParameterClause = peek() == .leftParen
        guard hasExplicitParameterClause else {
            throw ParseError(
                "Callable declarations must declare an explicit parameter clause. Use derived \(name): Type for produced values."
            )
        }
        let parameters = try parseFunctionParameters()
        let returnType: TypeReference?
        if peek() == .arrow {
            try consume(.arrow)
            returnType = try parseTypeReferenceNode()
        } else {
            returnType = nil
        }
        registerVisibleCallableReturnType(
            targetType: targetType,
            name: name,
            returnType: returnType
        )
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return CallableDeclaration(
            macros: macros,
            targetType: targetType,
            name: name,
            genericParameters: genericParameters,
            hasExplicitParameterClause: hasExplicitParameterClause,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    mutating func parseBuilderCallableDeclaration() throws -> CallableDeclaration {
        try consume(.asterisk)

        let hookName: String
        switch peek() {
        case .identifier(let name):
            hookName = name
            advance()
        default:
            throw ParseError("Expected builder hook name.")
        }

        let mappedName: String
        switch hookName {
        case "expression":
            mappedName = "buildExpression"
        case "block":
            mappedName = "buildBlock"
        case "optional":
            mappedName = "buildOptional"
        case "either":
            mappedName = "buildEither"
        case "array":
            mappedName = "buildArray"
        default:
            throw ParseError("Unknown builder hook '\(hookName)'.")
        }

        let parameters = try parseFunctionParameters()
        let returnType: TypeReference?
        if peek() == .arrow {
            try consume(.arrow)
            returnType = try parseTypeReferenceNode()
        } else {
            returnType = nil
        }
        registerVisibleCallableReturnType(
            targetType: nil,
            name: mappedName,
            returnType: returnType
        )
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return CallableDeclaration(
            macros: [],
            targetType: nil,
            name: mappedName,
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    mutating func parseFunctionParameters() throws -> [NeatFunctionParameter] {
        try consume(.leftParen)

        var parameters: [NeatFunctionParameter] = []
        if peek() != .rightParen {
            while true {
                let macros = try parseMacroApplicationsIfPresent()
                let (localName, externalLabel) = try parseLabeledDeclarationName(
                    expecting: "parameter",
                    allowOmittedLocalName: false
                )

                var typeReference: TypeReference?
                var slotName: String?
                if peek() == .colon {
                    try consume(.colon)
                    if case .atAttribute(let slot, _) = peek() {
                        advance()
                        slotName = slot
                    } else {
                        typeReference = try parseTypeReferenceNode()
                    }
                }

                parameters.append(
                    NeatFunctionParameter(
                        macros: macros,
                        localName: localName,
                        externalLabel: externalLabel,
                        typeReference: typeReference,
                        slotName: slotName
                    )
                )

                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return parameters
    }

    mutating func parseInitializerDeclaration() throws -> InitializerDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        guard case .identifier(let name) = peek(), name == "init" else {
            throw ParseError("Expected initializer declaration.")
        }
        advance()
        let parameters = try parseFunctionParameters()
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return InitializerDeclaration(macros: macros, parameters: parameters, body: body)
    }

    func isInitializerDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        guard case .identifier(let name) = peek(offset: offset), name == "init" else {
            return false
        }
        return peek(offset: offset + 1) == .leftParen
    }

    mutating func registerVisibleCallableReturnType(
        targetType: TypeReference?,
        name: String,
        returnType: TypeReference?
    ) {
        guard let returnType else {
            return
        }

        currentCallableReturnTypes[name] = returnType

        if let targetType {
            currentCallableReturnTypes["\(targetType.displayName).\(name)"] = returnType
        }
    }

    func isCallableStart() -> Bool {
        if isBuilderCallableStart() {
            return true
        }
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        if peek(offset: offset) == .keyword(NeatSyntax.Keyword.function.rawValue) {
            return true
        }
        if case .identifier = peek(offset: offset),
            peek(offset: offset + 1) == .keyword(NeatSyntax.Keyword.function.rawValue)
        {
            return true
        }
        return false
    }

    func isBuilderDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        guard peek(offset: offset) == .asterisk else { return false }
        guard case .identifier(let name) = peek(offset: offset + 1), name == "builder" else {
            return false
        }
        guard case .identifier = peek(offset: offset + 2) else { return false }
        return peek(offset: offset + 3) == .leftBrace
    }

    func isBuilderCallableStart() -> Bool {
        guard peek() == .asterisk else { return false }
        guard case .identifier(let name) = peek(offset: 1) else { return false }
        return ["expression", "block", "optional", "either", "array"].contains(name)
    }

    func validateCallableDeclarations(_ callables: [CallableDeclaration]) throws {
        var seen: Set<String> = []
        for callable in callables {
            let signatures = Set(
                callableSignatureKeys(
                    targetType: callable.targetType,
                    name: callable.name,
                    parameters: callable.parameters
                )
            )
            for signature in signatures {
                guard seen.insert(signature).inserted else {
                    throw ParseError(
                        "Duplicate callable declaration \(renderCallableSignature(targetType: callable.targetType, name: callable.name, parameters: callable.parameters))."
                    )
                }
            }
        }
    }

    func validateCallableReturnSemantics(_ callables: [CallableDeclaration]) throws {
        for callable in callables {
            guard let body = callable.body else { continue }

            let explicitReturnType = callable.returnType
            let needsValueReturn = callableRequiresValueReturn(
                explicitReturnType: explicitReturnType,
                expectedReturnType: explicitReturnType
            )

            let returnExpressions = collectReturnExpressions(in: body)

            if explicitReturnType == nil {
                if returnExpressions.contains(where: { $0 != nil }) {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetType: callable.targetType, name: callable.name, parameters: callable.parameters)) has no return type and cannot return a value."
                    )
                }
                continue
            }

            if needsValueReturn {
                guard blockAlwaysReturnsValue(body) else {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetType: callable.targetType, name: callable.name, parameters: callable.parameters)) declares return type \(explicitReturnType!.displayName) but does not return a value on all paths."
                    )
                }

                if returnExpressions.contains(where: { $0 == nil }) {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetType: callable.targetType, name: callable.name, parameters: callable.parameters)) declares return type \(explicitReturnType!.displayName) and cannot use bare return."
                    )
                }
            }

            guard let explicitReturnType, explicitReturnType.displayName != "Void" else {
                continue
            }

            let parameterTypes: [String: TypeReference] = callable.parameters.reduce(into: [:]) {
                result,
                parameter in
                guard let typeReference = parameter.typeReference else { return }
                result[parameter.localName] = typeReference
            }

            let accessibleTypes = accessibleContextTypes().merging(parameterTypes) { current, _ in
                current
            }

            for expression in returnExpressions.compactMap({ $0 }) {
                guard
                    let inferred = try? inferBootstrapExpressionType(
                        of: expression,
                        accessibleTypes: accessibleTypes
                    )
                else {
                    continue
                }

                if inferred.isLiteralLike {
                    continue
                }

                guard isCompatibleWithExpectedType(inferred, expected: explicitReturnType)
                else {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetType: callable.targetType, name: callable.name, parameters: callable.parameters)) expects return type \(explicitReturnType.displayName), got \(inferred.displayName)."
                    )
                }
            }
        }
    }

    func callableRequiresValueReturn(
        explicitReturnType: TypeReference?,
        expectedReturnType: TypeReference?
    ) -> Bool {
        guard explicitReturnType != nil else { return false }
        guard let expectedReturnType else { return true }
        return expectedReturnType.displayName != "Void"
    }

    func collectReturnExpressions(in statements: [Statement]) -> [Expression?] {
        var expressions: [Expression?] = []

        for statement in statements {
            switch statement {
            case .freestandingMacro(_, _, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))
            case .return(let expression):
                expressions.append(expression)

            case .forEach(_, _, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))

            case .whileLoop(_, let body):
                expressions.append(contentsOf: collectReturnExpressions(in: body))

            case .conditional(let branches):
                for branch in branches {
                    expressions.append(contentsOf: collectReturnExpressions(in: branch.body))
                }

            case .switchStatement(_, let cases, let defaultBody):
                for switchCase in cases {
                    expressions.append(contentsOf: collectReturnExpressions(in: switchCase.body))
                }
                if let defaultBody {
                    expressions.append(contentsOf: collectReturnExpressions(in: defaultBody))
                }

            default:
                break
            }
        }

        return expressions
    }

    func blockAlwaysReturnsValue(_ statements: [Statement]) -> Bool {
        for statement in statements {
            if statementAlwaysReturnsValue(statement) {
                return true
            }
        }
        return false
    }

    func statementAlwaysReturnsValue(_ statement: Statement) -> Bool {
        switch statement {
        case .freestandingMacro(_, _, let body):
            return blockAlwaysReturnsValue(body)
        case .return(let expression):
            return expression != nil

        case .conditional(let branches):
            guard branches.contains(where: { $0.condition == nil }) else {
                return false
            }
            return branches.allSatisfy { blockAlwaysReturnsValue($0.body) }

        case .switchStatement(_, let cases, let defaultBody):
            guard let defaultBody else { return false }
            guard cases.allSatisfy({ blockAlwaysReturnsValue($0.body) }) else { return false }
            return blockAlwaysReturnsValue(defaultBody)

        default:
            return false
        }
    }

    func validateInitializerDeclarations(
        _ initializers: [InitializerDeclaration],
        availableDeriveds: [DerivedDeclaration],
        allowBodylessInitializers: Bool = false
    ) throws {
        let availableSlotNames = Set(availableDeriveds.map(\.name))

        var seen: Set<String> = []
        for initializer in initializers {
            guard allowBodylessInitializers || initializer.body != nil else {
                throw ParseError(
                    "Explicit initializer \(renderInitializerSignature(parameters: initializer.parameters)) must include a body."
                )
            }

            let slotParameters = initializer.parameters.compactMap(\.slotName)
            let duplicateSlots = Dictionary(grouping: slotParameters, by: { $0 })
                .filter { $1.count > 1 }
                .keys
            if let slotName = duplicateSlots.sorted().first {
                throw ParseError(
                    "Initializer \(renderInitializerSignature(parameters: initializer.parameters)) binds slot @\(slotName) more than once."
                )
            }

            for slotName in slotParameters {
                guard availableSlotNames.contains(slotName) else {
                    throw ParseError(
                        "Initializer \(renderInitializerSignature(parameters: initializer.parameters)) references unknown slot @\(slotName)."
                    )
                }
            }

            let signatures = Set(initializerSignatureKeys(parameters: initializer.parameters))
            for signature in signatures {
                guard seen.insert(signature).inserted else {
                    throw ParseError(
                        "Duplicate initializer declaration \(renderInitializerSignature(parameters: initializer.parameters))."
                    )
                }
            }
        }
    }

    func matches(_ lhs: [NeatFunctionParameter], _ rhs: [NeatFunctionParameter]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy {
            $0.externalLabel == $1.externalLabel
                && $0.typeReference == $1.typeReference
                && $0.slotName == $1.slotName
        }
    }

    func callableSignatureKeys(
        targetType: TypeReference?,
        name: String,
        parameters: [NeatFunctionParameter]
    ) -> [String] {
        signatureParameterVariants(parameters).map { variant in
            let rendered = variant.map(parameterSignatureKey).joined(separator: ",")
            return "\(targetType?.displayName ?? "_")@\(name)(\(rendered))"
        }
    }

    func renderCallableSignature(
        targetType: TypeReference?,
        name: String,
        parameters: [NeatFunctionParameter]
    ) -> String {
        let rendered = parameters.map(renderParameterSignature).joined(separator: ", ")
        if let targetType {
            return "\(targetType.displayName)@\(name)(\(rendered))"
        }
        return "@\(name)(\(rendered))"
    }

    func initializerSignatureKeys(parameters: [NeatFunctionParameter]) -> [String] {
        signatureParameterVariants(parameters).map { variant in
            variant.map(parameterSignatureKey).joined(separator: ",")
        }
    }

    func renderInitializerSignature(parameters: [NeatFunctionParameter]) -> String {
        let rendered = parameters.map(renderParameterSignature).joined(separator: ", ")
        return "init(\(rendered))"
    }

    func parameterSignatureKey(_ parameter: NeatFunctionParameter) -> String {
        let label = parameter.externalLabel ?? "_"
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
            ?? "_"
        return "\(label):\(typeName)"
    }

    func renderParameterSignature(_ parameter: NeatFunctionParameter) -> String {
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
            ?? "_"
        if let externalLabel = parameter.externalLabel {
            if externalLabel == parameter.localName {
                return "\(parameter.localName): \(typeName)"
            }
            return "\(parameter.localName) \(externalLabel): \(typeName)"
        }
        return "\(parameter.localName) _: \(typeName)"
    }

    func signatureParameterVariants(_ parameters: [NeatFunctionParameter])
        -> [[NeatFunctionParameter]]
    {
        var variants: [[NeatFunctionParameter]] = []

        func build(index: Int, current: [NeatFunctionParameter]) {
            if index == parameters.count {
                variants.append(current)
                return
            }

            let parameter = parameters[index]
            if parameter.isOptional {
                build(index: index + 1, current: current)
            }

            build(index: index + 1, current: current + [parameter])
        }

        build(index: 0, current: [])

        return variants.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }

            let left = lhs.map(parameterSignatureKey).joined(separator: ",")
            let right = rhs.map(parameterSignatureKey).joined(separator: ",")

            return left < right
        }
    }
}
