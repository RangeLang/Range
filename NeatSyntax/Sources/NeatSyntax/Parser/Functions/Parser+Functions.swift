import Foundation

extension Parser {
    mutating func parseCallableDeclaration() throws -> CallableDeclaration {
        if isBuilderCallableStart() {
            return try parseBuilderCallableDeclaration()
        }

        var targetName: String?
        if case .identifier(let target) = peek(),
            peek(offset: 1) == .keyword(NeatSyntax.Keyword.function.rawValue)
        {
            targetName = target
            advance()
        }

        guard peek() == .keyword(NeatSyntax.Keyword.function.rawValue) else {
            throw ParseError("Expected callable declaration starting with function.")
        }
        advance()

        let name = try consumeCallableName()
        let hasExplicitParameterClause = peek() == .leftParen
        guard hasExplicitParameterClause else {
            throw ParseError(
                "Callable declarations must declare an explicit parameter clause. Use derived \(name): Type for produced values."
            )
        }
        let parameters = try parseFunctionParameters()
        let returnTypeName: String?
        if peek() == .arrow {
            try consume(.arrow)
            returnTypeName = try consumeTypeReference()
        } else {
            returnTypeName = nil
        }
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return CallableDeclaration(
            targetName: targetName,
            name: name,
            hasExplicitParameterClause: hasExplicitParameterClause,
            parameters: parameters,
            returnTypeName: returnTypeName,
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
        let returnTypeName: String?
        if peek() == .arrow {
            try consume(.arrow)
            returnTypeName = try consumeTypeReference()
        } else {
            returnTypeName = nil
        }
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return CallableDeclaration(
            targetName: nil,
            name: mappedName,
            hasExplicitParameterClause: true,
            parameters: parameters,
            returnTypeName: returnTypeName,
            body: body
        )
    }

    mutating func parseFunctionParameters() throws -> [NeatFunctionParameter] {
        try consume(.leftParen)

        var parameters: [NeatFunctionParameter] = []
        if peek() != .rightParen {
            while true {
                let (localName, externalLabel) = try parseLabeledDeclarationName(
                    expecting: "parameter",
                    allowOmittedLocalName: false
                )

                var typeName: String?
                var slotName: String?
                if peek() == .colon {
                    try consume(.colon)
                    if case .atAttribute(let slot, _) = peek() {
                        advance()
                        slotName = slot
                    } else {
                        typeName = try consumeTypeReference()
                    }
                }

                parameters.append(
                    NeatFunctionParameter(
                        localName: localName,
                        externalLabel: externalLabel,
                        typeName: typeName,
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

    mutating func parseDerivedDeclaration() throws -> DerivedDeclaration {
        let builderName = try parseBuilderDirectiveIfPresent()
        try consumeKeyword(.derived)
        let name = try consumeIdentifier()
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return DerivedDeclaration(
            builderName: builderName,
            name: name,
            typeName: typeName,
            body: body
        )
    }

    func validateDerivedDeclarations(_ deriveds: [DerivedDeclaration]) throws {
        for derived in deriveds {
            guard let body = derived.body else { continue }

            if derived.builderName != nil {
                continue
            }

            if derived.isVariadic {
                for statement in body {
                    guard case .expression = statement else {
                        throw ParseError(
                            "Variadic derived \(derived.name): \(derived.typeName) can only contain top-level expression statements."
                        )
                    }
                }
                continue
            }

            let topLevelExpressions = body.compactMap { statement -> Expression? in
                guard case .expression(let expression) = statement else { return nil }
                return expression
            }

            if topLevelExpressions.count > 1 && topLevelExpressions.count == body.count {
                throw ParseError(
                    "Derived \(derived.name): \(derived.typeName) must produce a single value. Use \(derived.typeName)... if you want to collect multiple sibling expressions."
                )
            }
        }
    }

    func validateBuilderDeclarations(in declarations: [ConstructDeclaration]) throws {
        let declarationsByName = Dictionary(
            uniqueKeysWithValues: declarations.map { ($0.name, $0) })

        for declaration in declarations {
            for derived in declaration.deriveds {
                guard let builderName = derived.builderName else { continue }
                guard let builder = declarationsByName[builderName] else {
                    throw ParseError(
                        "Derived \(derived.name): \(derived.typeName) references unknown builder \(builderName)."
                    )
                }
                guard builder.kind == .builder else {
                    throw ParseError(
                        "Derived \(derived.name): \(derived.typeName) references \(builderName), but it is not declared as a builder."
                    )
                }

                let availableHooks = Set(builder.callables.map(\.name))
                let requiredHooks = requiredBuilderHooks(for: derived)

                let missingHooks = requiredHooks.subtracting(availableHooks).sorted()
                if !missingHooks.isEmpty {
                    throw ParseError(
                        "Builder \(builderName) is missing required hook functions for derived \(derived.name): \(missingHooks.joined(separator: ", "))."
                    )
                }
            }
        }
    }

    func requiredBuilderHooks(for derived: DerivedDeclaration) -> Set<String> {
        guard let body = derived.body else {
            return []
        }

        var hooks: Set<String> = ["buildExpression", "buildBlock"]
        collectBuilderHooks(from: body, into: &hooks)
        return hooks
    }

    func collectBuilderHooks(from statements: [Statement], into hooks: inout Set<String>) {
        for statement in statements {
            switch statement {
            case .expression:
                continue
            case .declaration:
                continue
            case .assignment, .compoundAssignment:
                continue
            case .environmentProvision:
                continue
            case .return, .break, .continue:
                continue
            case .forEach(_, _, let body):
                hooks.insert("buildArray")
                collectBuilderHooks(from: body, into: &hooks)
            case .whileLoop(_, let body):
                hooks.insert("buildArray")
                collectBuilderHooks(from: body, into: &hooks)
            case .conditional(let branches):
                if branches.contains(where: { $0.condition == nil }) {
                    hooks.insert("buildEither")
                } else {
                    hooks.insert("buildOptional")
                }

                for branch in branches {
                    collectBuilderHooks(from: branch.body, into: &hooks)
                }
            case .switchStatement(_, let cases, let defaultBody):
                hooks.insert("buildEither")
                for `case` in cases {
                    collectBuilderHooks(from: `case`.body, into: &hooks)
                }
                if let defaultBody {
                    collectBuilderHooks(from: defaultBody, into: &hooks)
                }
            }
        }
    }

    func isBuilderDirectiveStart() -> Bool {
        guard peek() == .asterisk else { return false }

        switch peek(offset: 1) {
        case .identifier(let name), .keyword(let name):
            guard name != "environment", name != "builder" else { return false }
        default:
            return false
        }
        return true
    }

    mutating func parseBuilderDirectiveIfPresent() throws -> String? {
        guard isBuilderDirectiveStart() else {
            return nil
        }

        try consume(.asterisk)
        switch peek() {
        case .identifier(let name), .keyword(let name):
            advance()
            return name
        default:
            throw ParseError("Expected *BuilderName directive.")
        }
    }

    mutating func parseInitializerDeclaration() throws -> InitializerDeclaration {
        guard case .identifier(let name) = peek(), name == "init" else {
            throw ParseError("Expected initializer declaration.")
        }
        advance()
        let parameters = try parseFunctionParameters()
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return InitializerDeclaration(parameters: parameters, body: body)
    }

    func isDerivedDeclarationStart() -> Bool {
        if isBuilderDirectiveStart() {
            return true
        }
        guard peek() == .keyword(NeatSyntax.Keyword.derived.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1) else { return false }
        return peek(offset: 2) == .colon
    }

    func isInitializerDeclarationStart() -> Bool {
        guard case .identifier(let name) = peek(), name == "init" else {
            return false
        }
        return peek(offset: 1) == .leftParen
    }

    func isCallableStart() -> Bool {
        if isBuilderCallableStart() {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.function.rawValue) {
            return true
        }
        if case .identifier = peek(),
            peek(offset: 1) == .keyword(NeatSyntax.Keyword.function.rawValue)
        {
            return true
        }
        return false
    }

    func isBuilderDeclarationStart() -> Bool {
        guard peek() == .asterisk else { return false }
        guard case .identifier(let name) = peek(offset: 1), name == "builder" else {
            return false
        }
        guard case .identifier = peek(offset: 2) else { return false }
        return peek(offset: 3) == .leftBrace
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
                    targetName: callable.targetName,
                    name: callable.name,
                    parameters: callable.parameters
                )
            )
            for signature in signatures {
                guard seen.insert(signature).inserted else {
                    throw ParseError(
                        "Duplicate callable declaration \(renderCallableSignature(targetName: callable.targetName, name: callable.name, parameters: callable.parameters))."
                    )
                }
            }
        }
    }

    func validateCallableReturnSemantics(_ callables: [CallableDeclaration]) throws {
        for callable in callables {
            guard let body = callable.body else { continue }

            let explicitReturnType = callable.returnTypeName
            let expectedBuiltinType = explicitReturnType.flatMap { builtinType(from: $0) }
            let needsValueReturn = callableRequiresValueReturn(
                explicitReturnType: explicitReturnType,
                expectedBuiltinType: expectedBuiltinType
            )

            let returnExpressions = collectReturnExpressions(in: body)

            if explicitReturnType == nil {
                if returnExpressions.contains(where: { $0 != nil }) {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetName: callable.targetName, name: callable.name, parameters: callable.parameters)) has no return type and cannot return a value."
                    )
                }
                continue
            }

            if needsValueReturn {
                guard blockAlwaysReturnsValue(body) else {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetName: callable.targetName, name: callable.name, parameters: callable.parameters)) declares return type \(explicitReturnType!) but does not return a value on all paths."
                    )
                }

                if returnExpressions.contains(where: { $0 == nil }) {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetName: callable.targetName, name: callable.name, parameters: callable.parameters)) declares return type \(explicitReturnType!) and cannot use bare return."
                    )
                }
            }

            guard let expectedBuiltinType, expectedBuiltinType != .void else {
                continue
            }

            let parameterTypes: [String: BuiltinType] = callable.parameters.reduce(into: [:]) {
                result,
                parameter in
                guard
                    let typeName = parameter.typeName,
                    let builtin = builtinType(from: typeName)
                else { return }
                result[parameter.localName] = builtin
            }

            let accessibleTypes = accessibleBuiltinTypes().merging(parameterTypes) { current, _ in
                current
            }

            for expression in returnExpressions.compactMap({ $0 }) {
                guard
                    let inferred = try? inferType(of: expression, accessibleTypes: accessibleTypes)
                else {
                    continue
                }

                guard isCompatibleReturnType(expected: expectedBuiltinType, actual: inferred) else {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetName: callable.targetName, name: callable.name, parameters: callable.parameters)) expects return type \(expectedBuiltinType.displayName), got \(inferred.displayName)."
                    )
                }
            }
        }
    }

    func callableRequiresValueReturn(
        explicitReturnType: String?,
        expectedBuiltinType: BuiltinType?
    ) -> Bool {
        guard explicitReturnType != nil else { return false }
        guard let expectedBuiltinType else { return true }
        return expectedBuiltinType != .void
    }

    func collectReturnExpressions(in statements: [Statement]) -> [Expression?] {
        var expressions: [Expression?] = []

        for statement in statements {
            switch statement {
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

    func isCompatibleReturnType(expected: BuiltinType, actual: BuiltinType) -> Bool {
        if actual == .none {
            return expected.isOptional
        }
        return isCompatibleStateType(expected, inferredType: actual)
    }

    func validateInitializerDeclarations(
        _ initializers: [InitializerDeclaration],
        availableDeriveds: [DerivedDeclaration]
    ) throws {
        let availableSlotNames = Set(availableDeriveds.map(\.name))

        var seen: Set<String> = []
        for initializer in initializers {
            guard initializer.body != nil else {
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
                && $0.typeName == $1.typeName
                && $0.slotName == $1.slotName
        }
    }

    func callableSignatureKeys(
        targetName: String?,
        name: String,
        parameters: [NeatFunctionParameter]
    ) -> [String] {
        signatureParameterVariants(parameters).map { variant in
            let rendered = variant.map(parameterSignatureKey).joined(separator: ",")
            return "\(targetName ?? "_")@\(name)(\(rendered))"
        }
    }

    func renderCallableSignature(
        targetName: String?,
        name: String,
        parameters: [NeatFunctionParameter]
    ) -> String {
        let rendered = parameters.map(renderParameterSignature).joined(separator: ", ")
        if let targetName {
            return "\(targetName)@\(name)(\(rendered))"
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
        let typeName = parameter.slotName.map { "@\($0)" } ?? parameter.typeName ?? "_"
        return "\(label):\(typeName)"
    }

    func renderParameterSignature(_ parameter: NeatFunctionParameter) -> String {
        let typeName = parameter.slotName.map { "@\($0)" } ?? parameter.typeName ?? "_"
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
