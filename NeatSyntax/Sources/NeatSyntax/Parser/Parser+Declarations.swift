import Foundation

extension Parser {
    public mutating func parseDeclaration() throws -> DeclarationNode {
        var objects: [ObjectType] = []
        while true {
            switch peek() {
            case .keyword(NeatSyntax.Keyword.function.rawValue):
                objects.append(.neatFunction(try parseNeatFunctionDeclaration()))
            case .keyword(NeatSyntax.Keyword.typeExtension.rawValue):
                objects.append(.typeExtension(try parseTypeExtensionDeclaration()))
            case .atAttribute(let attr, _) where attr == "StyleModifier":
                try skipStyleModifierDeclaration()
            default:
                break
            }

            switch peek() {
            case .keyword(NeatSyntax.Keyword.function.rawValue),
                .keyword(NeatSyntax.Keyword.typeExtension.rawValue):
                continue
            case .atAttribute(let attr, _) where attr == "StyleModifier":
                continue
            default:
                break
            }
            break
        }

        let attribute = NeatSyntax.attributeApplication(for: peek())
        let kind = try parseDeclarationKind()
        let header = try parseDeclarationHeader(after: attribute)
        let name = header.name
        let conformances = header.conformances
        let projectionTarget = header.projectionTarget

        var states: [StateDeclaration] = []
        var cases: [EnumCaseDeclaration] = []
        var members: [MemberDeclaration] = []
        var callables: [CallableDeclaration] = []
        var body: ViewNode?

        if peek() == .leftBrace {
            try consume(.leftBrace)

            currentStateTypes = [:]
            while peek() == .keyword(NeatSyntax.Keyword.state.rawValue)
                || isCaseDeclarationStart() || isMemberDeclarationStart()
                || isCallableStart()
            {
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
                body = try parseDeclarationBody()
                currentStateNames = []
                currentMutableStateNames = []
            }

            currentStateTypes = [:]
            currentMutableStateNames = []

            try consume(.rightBrace)
        }

        try consume(.eof)

        try validateCallableDeclarations(callables)

        return DeclarationNode(
            kind: kind,
            attribute: attribute,
            name: name,
            conformances: conformances,
            projectionTarget: projectionTarget,
            objects: objects,
            cases: cases,
            states: states,
            members: members,
            callables: callables,
            body: body
        )
    }

    mutating func parseNeatFunctionDeclaration() throws -> NeatFunctionDeclaration {
        try consumeKeyword(.function)
        let name = try consumeIdentifier()
        let parameters = try parseFunctionParameters()

        var returnType: String?
        if peek() == .arrow {
            try consume(.arrow)
            returnType = try consumeTypeReference()
        }

        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }

        return NeatFunctionDeclaration(name: name, parameters: parameters, returnType: returnType)
    }

    mutating func parseCallableDeclaration() throws -> CallableDeclaration {
        guard case .hashDirective(let name) = peek() else {
            throw ParseError("Expected callable declaration.")
        }
        advance()
        let parameters = try parseFunctionParameters()
        let hasBody = peek() == .leftBrace
        if hasBody {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return CallableDeclaration(name: name, parameters: parameters, hasBody: hasBody)
    }

    mutating func skipStyleModifierDeclaration() throws {
        try consume(.atAttribute(name: "StyleModifier", argument: nil))
        let name = try consumeIdentifier()
        if peek() == .colon {
            throw ParseError(
                "@StyleModifier '\(name)' should not declare conformance; style modifiers are implicitly callable."
            )
        }
        if peek() == .leftBrace {
            try consume(.leftBrace)
            while peek() != .rightBrace {
                advance()
            }
            try consume(.rightBrace)
        }
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
                let firstName = try consumeIdentifier()
                let parameterName: String
                if case .identifier(let secondName) = peek(), peek(offset: 1) == .colon {
                    advance()
                    parameterName = secondName == "_" ? firstName : secondName
                } else {
                    parameterName = firstName
                }
                var typeName: String?
                if peek() == .colon {
                    try consume(.colon)
                    typeName = try consumeTypeReference()
                }

                parameters.append(
                    NeatFunctionParameter(name: parameterName, typeName: typeName)
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

    mutating func parseDeclarationKind() throws -> DeclarationKind {
        guard let kind = NeatSyntax.declarationKind(for: peek()) else {
            throw ParseError("Expected @main or a declaration attribute.")
        }
        advance()
        return kind
    }

    mutating func parseDeclarationHeader(after attribute: AttributeApplication?) throws
        -> (name: String, conformances: [String], projectionTarget: String?)
    {
        guard let attribute else {
            throw ParseError("Expected declaration attribute.")
        }

        if attribute.name == "main" {
            let name = try consumeIdentifier()
            let conformances = try parseConformanceListIfPresent()
            guard !conformances.isEmpty else {
                throw ParseError(
                    "@main requires an entry contract, e.g. @main MyApp: App { ... }."
                )
            }
            return (name, conformances, nil)
        }

        if peek() == .colon || peek() == .keyword(NeatSyntax.Keyword.projection.rawValue)
            || peek() == .leftBrace
        {
            let conformances = try parseConformanceListIfPresent()
            let projectionTarget = try parseProjectionTargetIfPresent()
            return (attribute.name, conformances, projectionTarget)
        }

        throw ParseError(
            "Expected ':', 'on', or '{' after @\(attribute.name). Use @\(attribute.name) { ... }, @\(attribute.name): Protocol { ... }, or @\(attribute.name): Role on Target { ... }."
        )
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
        try consumeKeyword(.variable)
        let name = try consumeIdentifier()
        try consume(.colon)
        let typeName = try consumeTypeReference()
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return MemberDeclaration(name: name, typeName: typeName)
    }

    func isMemberDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.variable.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1), peek(offset: 2) == .colon else {
            return false
        }
        return true
    }

    func isBodyMemberStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.variable.rawValue) else {
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
        if case .hashDirective = peek() {
            return true
        }
        return false
    }

    func validateCallableDeclarations(_ callables: [CallableDeclaration]) throws {
        var seen: Set<String> = []
        for callable in callables {
            let signature = callableSignatureKey(
                name: callable.name, parameters: callable.parameters)
            guard seen.insert(signature).inserted else {
                throw ParseError(
                    "Duplicate callable declaration \(renderCallableSignature(name: callable.name, parameters: callable.parameters))."
                )
            }
        }
    }

    func matches(_ lhs: [NeatFunctionParameter], _ rhs: [NeatFunctionParameter]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { $0.typeName == $1.typeName }
    }

    func callableSignatureKey(name: String, parameters: [NeatFunctionParameter]) -> String {
        let rendered = parameters.map(\.typeName).map { $0 ?? "_" }.joined(separator: ",")
        return "\(name)(\(rendered))"
    }

    func renderCallableSignature(name: String, parameters: [NeatFunctionParameter]) -> String {
        let rendered = parameters.map { parameter in
            let typeName = parameter.typeName ?? "_"
            return "\(parameter.name): \(typeName)"
        }.joined(separator: ", ")
        return "#\(name)(\(rendered))"
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
