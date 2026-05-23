import Foundation

extension Parser {
    func localBindings(for parameters: [RangeFunctionParameter]) -> [String: LocalBindingSymbol] {
        Dictionary(
            uniqueKeysWithValues: parameters.compactMap { parameter in
                guard let typeReference = parameter.typeReference else {
                    return nil
                }
                return (
                    parameter.localName,
                    LocalBindingSymbol(
                        kind: parameter.isBinding ? .mutable : .constant,
                        type: typeReference
                    )
                )
            }
        )
    }

    mutating func parseCallableDeclaration(signatureOnly: Bool = false) throws
        -> CallableDeclaration
    {
        if isBuilderCallableStart() {
            return try parseBuilderCallableDeclaration(signatureOnly: signatureOnly)
        }

        let macros = try parseMacroApplicationsIfPresent()

        if isBackgroundWorkerStart(at: 0) {
            return try rejectNamedBackgroundCallableDeclaration()
        }

        if case .atAttribute(let name, _) = peek(),
            name == "background",
            peek(offset: 1) == .keyword(RangeSyntax.Keyword.function.rawValue)
        {
            throw ParseError(
                "Named @background callables are not supported."
            )
        }

        let attribute = parseAttributeIfPresent(before: .function)
        var targetType: TypeReference?
        if case .identifier(let target) = peek(),
            peek(offset: 1) == .keyword(RangeSyntax.Keyword.function.rawValue)
        {
            targetType = .named(target)
            advance()
        }

        guard peek() == .keyword(RangeSyntax.Keyword.function.rawValue) else {
            throw ParseError("Expected callable declaration starting with function.")
        }
        advance()

        let name = try consumeCallableName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        let hasExplicitParameterClause = peek() == .leftParen
        guard hasExplicitParameterClause else {
            throw ParseError(
                "Callable declarations must declare an explicit parameter clause. Use derived \(name): Type for produced values."
            )
        }
        let parameters = try parseFunctionParameters(
            allowOmittedLocalName: signatureOnly
        )
        let returnType = try parseCallableReturnTypeIfPresent(kind: "Function")
        registerVisibleCallableReturnType(
            targetType: targetType,
            name: name,
            returnType: returnType
        )
        let body: [Statement]?
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            }
            body = nil
        } else {
            body =
                peek() == .leftBrace
                ? try parseStatementBlock(baseLocalBindings: localBindings(for: parameters)) : nil
        }
        return CallableDeclaration(
            macros: macros,
            attribute: attribute,
            targetType: targetType,
            receiverType: targetType ?? currentSelfType,
            name: name,
            genericParameters: genericParameters,
            hasExplicitParameterClause: hasExplicitParameterClause,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    mutating func rejectNamedBackgroundCallableDeclaration() throws
        -> CallableDeclaration
    {
        guard case .atAttribute(let name, _) = peek(), name == "background" else {
            throw ParseError("Expected named @background callable declaration.")
        }

        advance()
        let callableName = try consumeCallableName()

        if peek() == .less {
            try skipGenericParameterClauseIfPresent()
        }

        if peek() == .leftParen {
            _ = try parseFunctionParameters()
        }

        if peek() == .colon || peek() == .arrow {
            advance()
            _ = try parseTypeReferenceNode()
        }

        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }

        throw ParseError(
            "Named @background callables are not supported: \(callableName)."
        )
    }

    mutating func parseBuilderCallableDeclaration(signatureOnly: Bool = false) throws
        -> CallableDeclaration
    {
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
        let returnType = try parseCallableReturnTypeIfPresent(kind: "Builder hook")
        registerVisibleCallableReturnType(
            targetType: nil,
            name: mappedName,
            returnType: returnType
        )
        let body: [Statement]?
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            }
            body = nil
        } else {
            body =
                peek() == .leftBrace
                ? try parseStatementBlock(baseLocalBindings: localBindings(for: parameters)) : nil
        }
        return CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            receiverType: currentSelfType,
            name: mappedName,
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    mutating func parseCallableReturnTypeIfPresent(kind: String) throws -> TypeReference? {
        if peek() == .arrow {
            throw ParseError(
                "\(kind) return types use ': ReturnType', not '-> ReturnType'.",
                range: currentRange()
            )
        }

        guard peek() == .colon else {
            return nil
        }

        try consume(.colon)
        return try parseTypeReferenceNode()
    }

    mutating func parseFunctionParameters(
        allowSyntaxCapture: Bool = false,
        allowOmittedLocalName: Bool = false
    ) throws
        -> [RangeFunctionParameter]
    {
        try consume(.leftParen)

        var parameters: [RangeFunctionParameter] = []
        if peek() != .rightParen {
            while true {
                let macros = try parseMacroApplicationsIfPresent()
                let (localName, externalLabel) = try parseLabeledDeclarationName(
                    expecting: "parameter",
                    allowOmittedLocalName: allowOmittedLocalName
                )

                var typeReference: TypeReference?
                var slotName: String?
                var isBinding = false
                var capturesSyntax = false
                if peek() == .colon {
                    try consume(.colon)
                    if case .atAttribute(let slot, _) = peek() {
                        advance()
                        slotName = slot
                    } else {
                        if case .keyword(RangeSyntax.Keyword.binding.rawValue) = peek() {
                            advance()
                            isBinding = true
                        }
                        if case .identifier(let name) = peek(), name == "capture" {
                            if isBinding {
                                throw ParseError(
                                    "binding capture parameters are not supported."
                                )
                            }
                            guard allowSyntaxCapture else {
                                throw ParseError(
                                    "capture parameters are only valid in macro declarations."
                                )
                            }
                            advance()
                            capturesSyntax = true
                        }
                        typeReference = try parseTypeReferenceNode()
                    }
                }

                let defaultValue: Expression?
                if peek() == .equal {
                    try consume(.equal)
                    defaultValue = try parseExpression(terminatingAt: [.comma, .rightParen])
                } else {
                    defaultValue = nil
                }

                parameters.append(
                    RangeFunctionParameter(
                        macros: macros,
                        localName: localName,
                        externalLabel: externalLabel,
                        typeReference: typeReference,
                        defaultValue: defaultValue,
                        slotName: slotName,
                        isBinding: isBinding,
                        capturesSyntax: capturesSyntax
                    )
                )

                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return parameters
    }

    mutating func parseInitializerDeclaration(signatureOnly: Bool = false) throws -> InitializerDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        guard case .identifier(let name) = peek(), name == "init" else {
            throw ParseError("Expected initializer declaration.")
        }
        guard allowInitializerDeclarations else {
            throw ParseError(
                "Initializer declarations are no longer source syntax. Describe construct data with stored declarations and use functions for behavior."
            )
        }
        advance()
        let parameters = try parseFunctionParameters(
            allowOmittedLocalName: signatureOnly
        )
        let returnType: TypeReference?
        if peek() == .arrow {
            try consume(.arrow)
            let parsedReturnType = try parseTypeReferenceNode()
            try validateInitializerReturnType(parsedReturnType)
            returnType = parsedReturnType
        } else {
            returnType = nil
        }
        let body: [Statement]?
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            }
            body = nil
        } else {
            body =
                peek() == .leftBrace
                ? try parseStatementBlock(baseLocalBindings: localBindings(for: parameters)) : nil
        }
        return InitializerDeclaration(
            macros: macros,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    func validateInitializerReturnType(_ returnType: TypeReference) throws {
        guard case .generic(let base, let arguments) = returnType,
            case .named("Result") = base,
            arguments.count == 2,
            case .named("Self") = arguments[0]
        else {
            throw ParseError(
                "Initializer return type must be Result<Self, Failure>."
            )
        }
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
        let resolvedReturnType = returnType ?? .named("Void")

        currentCallableReturnTypes[name] = resolvedReturnType

        if let targetType {
            currentCallableReturnTypes["\(targetType.displayName).\(name)"] = resolvedReturnType
        }
    }

    func isCallableStart() -> Bool {
        if isBuilderCallableStart() {
            return true
        }
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        if isBackgroundWorkerStart(at: offset) {
            return true
        }
        let attributeOffset: Int
        if case .atAttribute = peek(offset: offset),
            peek(offset: offset + 1) == .keyword(RangeSyntax.Keyword.function.rawValue)
        {
            attributeOffset = offset + 1
        } else {
            attributeOffset = offset
        }
        if peek(offset: attributeOffset) == .keyword(RangeSyntax.Keyword.function.rawValue) {
            return true
        }
        if case .identifier = peek(offset: attributeOffset),
            peek(offset: attributeOffset + 1) == .keyword(RangeSyntax.Keyword.function.rawValue)
        {
            return true
        }
        return false
    }

    private func isBackgroundWorkerStart(at offset: Int) -> Bool {
        guard case .atAttribute(let name, _) = peek(offset: offset), name == "background" else {
            return false
        }

        guard tokenCanStartCallableName(peek(offset: offset + 1)) else {
            return false
        }

        let next = peek(offset: offset + 2)
        return next == .leftParen || next == .less
    }

    private func tokenCanStartCallableName(_ token: Token) -> Bool {
        switch token {
        case .identifier, .keyword:
            return true
        default:
            return false
        }
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

    func validateCallableReturnSemantics(
        _ callables: [CallableDeclaration],
        allowBodylessCallables: Bool = false
    ) throws {
        for callable in callables {
            guard let body = callable.body else {
                continue
            }

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

            if isVoidType(explicitReturnType!) {
                if returnExpressions.contains(where: { $0 != nil }) {
                    throw ParseError(
                        "Callable \(renderCallableSignature(targetType: callable.targetType, name: callable.name, parameters: callable.parameters)) declares return type Void and cannot return a value."
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
                    let inferred = try? inferExpressionType(
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
        return !isVoidType(expectedReturnType)
    }

    func isVoidType(_ typeReference: TypeReference) -> Bool {
        typeReference.displayName == "Void"
    }

    func collectReturnExpressions(in statements: [Statement]) -> [Expression?] {
        var expressions: [Expression?] = []

        for statement in statements {
            switch statement {
            case .macroInvocation(_, _, let body):
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

            case .background:
                continue
            case .deferBlock(let deferred):
                expressions.append(contentsOf: collectReturnExpressions(in: deferred.body))

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
        case .macroInvocation(_, _, let body):
            return blockAlwaysReturnsValue(body)
        case .return(let expression):
            return expression != nil

        case .conditional(let branches):
            guard branches.contains(where: { $0.condition == nil }) else {
                return false
            }
            return branches.allSatisfy { blockAlwaysReturnsValue($0.body) }

        case .switchStatement(_, let cases, let defaultBody):
            guard !cases.isEmpty else { return false }
            guard cases.allSatisfy({ blockAlwaysReturnsValue($0.body) }) else { return false }
            guard let defaultBody else { return true }
            return blockAlwaysReturnsValue(defaultBody)
        case .background:
            return false
        case .deferBlock(let deferred):
            return blockAlwaysReturnsValue(deferred.body)
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

    func matches(_ lhs: [RangeFunctionParameter], _ rhs: [RangeFunctionParameter]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy {
            $0.externalLabel == $1.externalLabel
                && $0.typeReference == $1.typeReference
                && $0.slotName == $1.slotName
                && $0.isBinding == $1.isBinding
                && $0.capturesSyntax == $1.capturesSyntax
        }
    }

    func callableSignatureKeys(
        targetType: TypeReference?,
        name: String,
        parameters: [RangeFunctionParameter]
    ) -> [String] {
        signatureParameterVariants(parameters).map { variant in
            let rendered = variant.map(parameterSignatureKey).joined(separator: ",")
            return "\(targetType?.displayName ?? "_")@\(name)(\(rendered))"
        }
    }

    func renderCallableSignature(
        targetType: TypeReference?,
        name: String,
        parameters: [RangeFunctionParameter]
    ) -> String {
        let rendered = parameters.map(renderParameterSignature).joined(separator: ", ")
        if let targetType {
            return "\(targetType.displayName)@\(name)(\(rendered))"
        }
        return "@\(name)(\(rendered))"
    }

    func initializerSignatureKeys(parameters: [RangeFunctionParameter]) -> [String] {
        signatureParameterVariants(parameters).map { variant in
            variant.map(parameterSignatureKey).joined(separator: ",")
        }
    }

    func renderInitializerSignature(parameters: [RangeFunctionParameter]) -> String {
        let rendered = parameters.map(renderParameterSignature).joined(separator: ", ")
        return "init(\(rendered))"
    }

    func parameterSignatureKey(_ parameter: RangeFunctionParameter) -> String {
        let label = parameter.externalLabel ?? "_"
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
            ?? "_"
        return "\(label):\(typeName)"
    }

    func renderParameterSignature(_ parameter: RangeFunctionParameter) -> String {
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
            ?? "_"
        if let externalLabel = parameter.externalLabel {
            if externalLabel == parameter.localName {
                return "\(parameter.localName): \(typeName)"
            }
            return "\(externalLabel) \(parameter.localName): \(typeName)"
        }
        return "_ \(parameter.localName): \(typeName)"
    }

    func signatureParameterVariants(_ parameters: [RangeFunctionParameter])
        -> [[RangeFunctionParameter]]
    {
        var variants: [[RangeFunctionParameter]] = []

        func build(index: Int, current: [RangeFunctionParameter]) {
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
