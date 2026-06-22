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

        if case .macroAttribute(let name, _) = peek(),
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
        guard case .macroAttribute(let name, _) = peek(), name == "background" else {
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
                "\(kind) return type clause must be ': ReturnType'.",
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
                if allowOmittedLocalName {
                    let anonymousParameterStart = index
                    if let typeReference = try? parseTypeReferenceNode(),
                        peek() == .comma || peek() == .rightParen
                    {
                        parameters.append(
                            RangeFunctionParameter(
                                macros: macros,
                                name: "__anonymous\(parameters.count)",
                                typeReference: typeReference,
                                slotName: nil
                            )
                        )
                        guard peek() == .comma else { break }
                        advance()
                        continue
                    }
                    index = anonymousParameterStart
                }
                let localName = try parseParameterName()

                var typeReference: TypeReference?
                var slotName: String?
                var isBinding = false
                let captureMacros = macros.filter { $0.name == "capture" }
                let capturesSyntax = !captureMacros.isEmpty
                var captureMetadataType: TypeReference?
                if capturesSyntax {
                    guard allowSyntaxCapture else {
                        throw ParseError(
                            "@capture parameters are only valid in macro declarations."
                        )
                    }
                    guard captureMacros.count == 1 else {
                        throw ParseError(
                            "@capture parameters can only declare one capture annotation."
                        )
                    }
                    guard captureMacros[0].genericArguments.count <= 1 else {
                        throw ParseError(
                            "@capture parameters can declare at most one metadata type."
                        )
                    }
                    captureMetadataType = captureMacros[0].genericArguments.first
                } else {
                    captureMetadataType = nil
                }
                if peek() == .colon {
                    try consume(.colon)
                    if case .macroAttribute(let slot, _) = peek() {
                        advance()
                        slotName = slot
                    } else {
                        if case .keyword(RangeSyntax.Keyword.binding.rawValue) = peek() {
                            advance()
                            isBinding = true
                        }
                        if capturesSyntax && isBinding {
                            throw ParseError(
                                "binding capture parameters are not supported."
                            )
                        }
                        typeReference = try parseTypeReferenceNode()
                    }
                }
                if capturesSyntax && captureMetadataType == nil {
                    captureMetadataType = typeReference
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
                        name: localName,
                        typeReference: typeReference,
                        defaultValue: defaultValue,
                        slotName: slotName,
                        isBinding: isBinding,
                        capturesSyntax: capturesSyntax,
                        captureMetadataType: captureMetadataType
                    )
                )

                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return parameters
    }

    private mutating func parseParameterName() throws -> String {
        let name: String
        switch peek() {
        case .identifier(let value):
            name = value
            advance()
        case .keyword(let value):
            name = value
            advance()
        default:
            throw ParseError("Expected parameter name.")
        }

        guard name != "_" else {
            throw ParseError("Parameter name cannot be '_'. Use a macro for hidden parameter behavior.")
        }

        switch peek() {
        case .identifier, .keyword:
            if peek(offset: 1) == .colon {
                throw ParseError(
                    "Parameter declarations use a single name; external labels are not supported."
                )
            }
        default:
            break
        }

        return name
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
        if case .macroAttribute = peek(offset: offset),
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
        guard case .macroAttribute(let name, _) = peek(offset: offset), name == "background" else {
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
            $0.name == $1.name
                && $0.typeReference == $1.typeReference
                && $0.slotName == $1.slotName
                && $0.isBinding == $1.isBinding
                && $0.capturesSyntax == $1.capturesSyntax
                && $0.captureMetadataType == $1.captureMetadataType
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
        let label = parameter.name
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
            ?? "_"
        return "\(label):\(typeName)"
    }

    func renderParameterSignature(_ parameter: RangeFunctionParameter) -> String {
        let typeName =
            parameter.slotName.map { "@\($0)" } ?? parameter.renderedTypeName
            ?? "_"
        return "\(parameter.name): \(typeName)"
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
