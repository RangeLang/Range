import Foundation

extension Parser {
    func isMainBlockStart() -> Bool {
        guard case .atAttribute(let name, _) = peek(), name == "main" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    public mutating func parseMainBlock() throws -> MainBlockNode {
        guard case .atAttribute(let name, _) = peek(), name == "main" else {
            throw ParseError("Expected @main block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: [:])
        try consume(.eof)
        return MainBlockNode(body: body)
    }

    public mutating func parseDeclaration() throws -> DeclarationNode {
        var objects: [ObjectType] = []
        while true {
            switch peek() {
            case .keyword(NeatSyntax.Keyword.typeExtension.rawValue):
                objects.append(.typeExtension(try parseTypeExtensionDeclaration()))
            default:
                break
            }

            switch peek() {
            case .keyword(NeatSyntax.Keyword.typeExtension.rawValue):
                continue
            default:
                break
            }
            break
        }

        let attribute = parseDeclarationAttributeIfPresent()
        let kind = try parseDeclarationKind(attribute: attribute)
        let header = try parseDeclarationHeader()
        let name = header.name
        let conformances = header.conformances
        let projectionTarget = header.projectionTarget

        var states: [StateDeclaration] = []
        var cases: [EnumCaseDeclaration] = []
        var bindings: [BindingDeclaration] = []
        var members: [MemberDeclaration] = []
        var initializers: [InitializerDeclaration] = []
        var callables: [CallableDeclaration] = []
        var body: ViewNode?

        if peek() == .leftBrace {
            try consume(.leftBrace)

            currentStateTypes = [:]
            while peek() == .keyword(NeatSyntax.Keyword.state.rawValue)
                || isCaseDeclarationStart() || isBindingDeclarationStart()
                || isMemberDeclarationStart()
                || isInitializerDeclarationStart()
                || isCallableStart()
            {
                currentBindingNames = Set(bindings.map(\.name))
                if isBodyMemberStart() {
                    break
                }
                if isCaseDeclarationStart() {
                    cases.append(contentsOf: try parseEnumCaseLine())
                    continue
                }
                if isMemberDeclarationStart() {
                    members.append(try parseMemberDeclaration())
                    continue
                }
                if isBindingDeclarationStart() {
                    bindings.append(try parseBindingDeclaration())
                    continue
                }
                if isInitializerDeclarationStart() {
                    initializers.append(try parseInitializerDeclaration())
                    continue
                }
                if isCallableStart() {
                    callables.append(try parseCallableDeclaration())
                    continue
                }

                let state = try parseState()
                states.append(state)
                currentStateTypes[state.name] = state.type
            }

            if peek() != .rightBrace, !isMemberDeclarationStart() || isBodyMemberStart() {
                currentStateNames = Set(states.map(\.name))
                currentMutableStateNames = Set(
                    states.compactMap { state in
                        if case .stored = state.storage { return state.name }
                        return nil
                    })
                currentBindingNames = Set(bindings.map(\.name))
                body = try parseDeclarationBody()
                currentStateNames = []
                currentMutableStateNames = []
                currentBindingNames = []
            }

            currentStateTypes = [:]
            currentMutableStateNames = []
            currentBindingNames = []

            try consume(.rightBrace)
        }

        try consume(.eof)

        try validateCallableDeclarations(callables)
        try validateInitializerDeclarations(initializers)

        return DeclarationNode(
            kind: kind,
            attribute: attribute,
            name: name,
            conformances: conformances,
            projectionTarget: projectionTarget,
            objects: objects,
            cases: cases,
            states: states,
            bindings: bindings,
            members: members,
            initializers: initializers,
            callables: callables,
            body: body
        )
    }

    mutating func parseCallableDeclaration() throws -> CallableDeclaration {
        var targetName: String?
        if case .identifier(let target) = peek(), case .atAttribute = peek(offset: 1) {
            targetName = target
            advance()
        }
        guard case .atAttribute(let name, _) = peek() else {
            throw ParseError("Expected callable declaration.")
        }
        advance()
        let parameters = try parseFunctionParameters()
        let body = peek() == .leftBrace ? try parseStatementBlock(baseLocalBindings: [:]) : nil
        return CallableDeclaration(
            targetName: targetName,
            name: name,
            parameters: parameters,
            body: body
        )
    }

    mutating func parseTypeExtensionDeclaration() throws -> TypeExtensionDeclaration {
        try consumeKeyword(.typeExtension)
        let typeName = try consumeTypeReference()
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return TypeExtensionDeclaration(typeName: typeName)
    }

    mutating func parseFunctionParameters() throws -> [NeatFunctionParameter] {
        try consume(.leftParen)

        var parameters: [NeatFunctionParameter] = []
        if peek() != .rightParen {
            while true {
                let localName = try consumeIdentifier()
                guard localName != "_" else {
                    throw ParseError("Parameter local name cannot be '_'.")
                }

                let externalLabel: String?
                if case .identifier(let secondName) = peek(), peek(offset: 1) == .colon {
                    advance()
                    externalLabel = secondName == "_" ? nil : secondName
                } else {
                    externalLabel = localName
                }

                var typeName: String?
                if peek() == .colon {
                    try consume(.colon)
                    typeName = try consumeTypeReference()
                }

                parameters.append(
                    NeatFunctionParameter(
                        localName: localName,
                        externalLabel: externalLabel,
                        typeName: typeName
                    )
                )

                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return parameters
    }

    mutating func parseEnumCaseLine() throws -> [EnumCaseDeclaration] {
        try consumeKeyword(.caseBranch)
        var declarations: [EnumCaseDeclaration] = []

        while true {
            let caseName = try consumeIdentifier()
            let associatedValues = try parseAssociatedValuesIfPresent()
            declarations.append(
                EnumCaseDeclaration(name: caseName, associatedValues: associatedValues)
            )

            guard peek() == .comma else {
                break
            }
            advance()
        }

        return declarations
    }

    func isCaseDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.caseBranch.rawValue)
    }

    mutating func parseAssociatedValuesIfPresent() throws -> [AssociatedValueDeclaration] {
        guard peek() == .leftParen else {
            return []
        }

        try consume(.leftParen)
        var associatedValues: [AssociatedValueDeclaration] = []

        while peek() != .rightParen {
            let firstIdentifier = try consumeIdentifier()

            if peek() == .colon {
                try consume(.colon)
                let typeName = try consumeTypeName()
                associatedValues.append(
                    AssociatedValueDeclaration(label: firstIdentifier, typeName: typeName)
                )
            } else {
                associatedValues.append(
                    AssociatedValueDeclaration(label: nil, typeName: firstIdentifier)
                )
            }

            guard peek() == .comma else {
                break
            }
            advance()
        }

        try consume(.rightParen)
        return associatedValues
    }

    mutating func parseState() throws -> StateDeclaration {
        try consumeKeyword(.state)
        let name = try consumeIdentifier()
        var explicitType: BuiltinType?
        if peek() == .colon {
            try consume(.colon)
            explicitType = try parseBuiltinType()
        }
        let storage: StateStorage
        let inferredType: BuiltinType

        if peek() == .equal {
            try consume(.equal)
            let initialValue = try parseExpression()
            if case .none = initialValue {
                guard let explicitType else {
                    throw ParseError(
                        "state '\(name)' initialized with none requires an explicit optional type.")
                }
                guard explicitType.isOptional else {
                    throw ParseError(
                        "state '\(name)' initialized with none requires an optional type.")
                }
                inferredType = explicitType
            } else {
                inferredType = try inferType(
                    of: initialValue,
                    stateTypes: currentStateTypes
                )
            }
            storage = .stored(initialValue)
        } else if peek() == .leftBrace {
            let body = try parseStatementBlock(baseLocalBindings: [:])
            guard let explicitType else {
                throw ParseError("Derived state '\(name)' requires an explicit type.")
            }
            inferredType = explicitType
            storage = .derived(body)
        } else {
            throw ParseError("state '\(name)' requires either `= expression` or a block body.")
        }

        if let explicitType, explicitType != inferredType {
            throw ParseError(
                "state '\(name)' expects \(explicitType.displayName), got \(inferredType.displayName)."
            )
        }
        return StateDeclaration(
            name: name, type: explicitType ?? inferredType, storage: storage)
    }

    mutating func parseDeclarationBody() throws -> ViewNode {
        if isBodyMemberStart() {
            try consumeKeyword(.variable)
            let name = try consumeIdentifier()
            guard name == "body" else {
                throw ParseError("Expected body member declaration.")
            }
            try consume(.colon)
            _ = try consumeTypeReference()
            let children = try parseViewBlock()

            let base: ViewNode = .vStack(children)
            return try parseModifiersIfPresent(for: base)
        }

        if case .identifier(let name) = peek(), name == "Body" {
            advance()
            let arguments = try parseInvocationArgumentsIfPresent()
            guard arguments.isEmpty else {
                throw ParseError("Body does not accept arguments.")
            }
            guard let block = try parseInvocationBlockIfPresent() else {
                throw ParseError("Body requires a block.")
            }
            guard case .views(let children) = block else {
                throw ParseError("Body block must contain views.")
            }

            let base: ViewNode = .vStack(children)
            return try parseModifiersIfPresent(for: base)
        }

        return try parseLayout()
    }

    mutating func parseDeclarationKind(attribute: AttributeApplication?) throws -> DeclarationKind {
        guard let kind = NeatSyntax.declarationKind(for: peek()) else {
            throw ParseError("Expected declaration starting with #.")
        }
        advance()
        if attribute?.name == "main" {
            return .entry
        }
        return kind
    }

    mutating func parseDeclarationHeader() throws
        -> (name: String, conformances: [String], projectionTarget: String?)
    {
        guard case .hashDirective(let name) = previous() else {
            throw ParseError("Expected declaration name after #.")
        }

        if peek() == .colon || peek() == .keyword(NeatSyntax.Keyword.projection.rawValue)
            || peek() == .leftBrace
        {
            let projectionTarget = try parseProjectionTargetIfPresent()
            let conformances = try parseConformanceListIfPresent()
            return (name, conformances, projectionTarget)
        }

        throw ParseError(
            "Expected 'on', ':', or '{' after #\(name). Use #\(name) { ... }, #\(name): Contract { ... }, or #\(name) on Target: Contract { ... }."
        )
    }

    mutating func parseDeclarationAttributeIfPresent() -> AttributeApplication? {
        guard case .atAttribute = peek(), case .hashDirective = peek(offset: 1) else {
            return nil
        }
        let attribute = NeatSyntax.attributeApplication(for: peek())
        advance()
        return attribute
    }

    mutating func parseConformanceListIfPresent() throws -> [String] {
        guard peek() == .colon else {
            return []
        }

        try consume(.colon)
        var conformances: [String] = []

        while true {
            conformances.append(try consumeTypeReference())
            guard peek() == .comma else { break }
            advance()
        }

        return conformances
    }

    mutating func parseProjectionTargetIfPresent() throws -> String? {
        guard peek() == .keyword(NeatSyntax.Keyword.projection.rawValue) else {
            return nil
        }

        try consumeKeyword(.projection)
        return try consumeTypeReference()
    }

    mutating func parseMemberDeclaration() throws -> MemberDeclaration {
        try consumeKeyword(.value)
        let name = try consumeIdentifier()
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let value: Expression?
        if peek() == .equal {
            try consume(.equal)
            value = try parseExpression()
        } else {
            value = nil
        }
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return MemberDeclaration(name: name, typeName: typeName, value: value)
    }

    mutating func parseBindingDeclaration() throws -> BindingDeclaration {
        try consumeKeyword(.binding)
        let name = try consumeIdentifier()
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let storage: BindingStorage
        if peek() == .leftBrace {
            let previousBindingNames = currentBindingNames
            currentBindingNames = previousBindingNames.union([name])
            storage = try parseDerivedBindingStorage(name: name)
            currentBindingNames = previousBindingNames.union([name])
        } else {
            storage = .plain
        }
        return BindingDeclaration(name: name, typeName: typeName, storage: storage)
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

    mutating func parseDerivedBindingStorage(name: String) throws -> BindingStorage {
        try consume(.leftBrace)

        var getterBody: [Statement]?
        var setterBody: [Statement]?

        while peek() != .rightBrace {
            if peek() == .keyword(NeatSyntax.Keyword.getter.rawValue) {
                guard getterBody == nil else {
                    throw ParseError("binding '\(name)' can only define one get block.")
                }
                try consumeKeyword(.getter)
                getterBody = try parseStatementBlock(baseLocalBindings: [:])
                continue
            }

            if peek() == .keyword(NeatSyntax.Keyword.setter.rawValue) {
                guard setterBody == nil else {
                    throw ParseError("binding '\(name)' can only define one set block.")
                }
                try consumeKeyword(.setter)
                setterBody = try parseStatementBlock(
                    baseLocalBindings: ["newValue": .constant]
                )
                continue
            }

            throw ParseError("Derived binding '\(name)' only supports get and set blocks.")
        }

        try consume(.rightBrace)

        guard let getterBody else {
            throw ParseError("Derived binding '\(name)' requires a get block.")
        }
        guard let setterBody else {
            throw ParseError("Derived binding '\(name)' requires a set block.")
        }

        return .derived(get: getterBody, set: setterBody)
    }

    func isMemberDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.value.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1), peek(offset: 2) == .colon else {
            return false
        }
        return true
    }

    func isBindingDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.binding.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1), peek(offset: 2) == .colon else {
            return false
        }
        return true
    }

    func isInitializerDeclarationStart() -> Bool {
        guard case .identifier(let name) = peek(), name == "init" else {
            return false
        }
        return peek(offset: 1) == .leftParen
    }

    func isBodyMemberStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.value.rawValue) else {
            return false
        }
        guard case .identifier(let name) = peek(offset: 1), name == "body" else {
            return false
        }
        guard peek(offset: 2) == .colon else {
            return false
        }
        return true
    }

    func isCallableStart() -> Bool {
        if case .atAttribute = peek() {
            return true
        }
        return false
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

    func validateInitializerDeclarations(_ initializers: [InitializerDeclaration]) throws {
        var seen: Set<String> = []
        for initializer in initializers {
            guard initializer.body != nil else {
                throw ParseError(
                    "Explicit initializer \(renderInitializerSignature(parameters: initializer.parameters)) must include a body."
                )
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
            $0.externalLabel == $1.externalLabel && $0.typeName == $1.typeName
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
        let typeName = parameter.typeName ?? "_"
        return "\(label):\(typeName)"
    }

    func renderParameterSignature(_ parameter: NeatFunctionParameter) -> String {
        let typeName = parameter.typeName ?? "_"
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

    mutating func skipUnknownBlockBody() throws {
        var depth = 0
        while true {
            switch peek() {
            case .leftBrace:
                depth += 1
                advance()
            case .rightBrace:
                if depth == 0 {
                    return
                }
                depth -= 1
                advance()
            case .eof:
                throw ParseError("Unterminated declaration block.")
            default:
                advance()
            }
        }
    }
}
