import Foundation

extension Parser {
    mutating func parseGenericParameterClauseIfPresent() throws -> [GenericParameter] {
        guard peek() == .less else {
            return []
        }

        try consume(.less)
        var parameters: [GenericParameter] = [try parseGenericParameter()]
        while peek() == .comma {
            advance()
            parameters.append(try parseGenericParameter())
        }
        try consume(.greater)
        return parameters
    }

    mutating func parseGenericParameter() throws -> GenericParameter {
        if peek() == .keyword(NeatSyntax.Keyword.let.rawValue) {
            try consumeKeyword(.let)
            let name = try consumeIdentifier()
            try consume(.colon)
            let typeReference = try parseTypeReferenceNode()
            let defaultValue: Expression?
            if peek() == .equal {
                try consume(.equal)
                defaultValue = try parseExpression(terminatingAt: [.comma, .greater])
            } else {
                defaultValue = nil
            }
            return .value(name: name, typeReference: typeReference, defaultValue: defaultValue)
        }

        let name = try consumeIdentifier()
        let constraint: TypeReference?
        if peek() == .colon {
            try consume(.colon)
            constraint = try parseTypeReferenceNode()
        } else {
            constraint = nil
        }

        let defaultArgument: TypeReference?
        if peek() == .equal {
            try consume(.equal)
            defaultArgument = try parseTypeReferenceNode()
        } else {
            defaultArgument = nil
        }

        return .type(name: name, constraint: constraint, defaultArgument: defaultArgument)
    }

    mutating func parseLabeledDeclarationName(
        expecting kind: String,
        allowOmittedLocalName: Bool = true
    ) throws -> (localName: String, externalLabel: String?) {
        let firstName: String
        switch peek() {
        case .identifier(let value):
            firstName = value
            advance()
        case .keyword(let value):
            firstName = value
            advance()
        default:
            throw ParseError("Expected \(kind) name.")
        }

        switch peek() {
        case .identifier(let secondName) where peek(offset: 1) == .colon:
            advance()
            guard secondName != "_" else {
                throw ParseError("\(kind.capitalized) internal name cannot be '_'.")
            }
            return (secondName, firstName == "_" ? nil : firstName)
        case .keyword(let secondName) where peek(offset: 1) == .colon:
            advance()
            guard secondName != "_" else {
                throw ParseError("\(kind.capitalized) internal name cannot be '_'.")
            }
            return (secondName, firstName == "_" ? nil : firstName)
        default:
            break
        }

        guard peek() == .colon else {
            throw ParseError("Expected ':' after \(kind) name.")
        }

        if firstName == "_" {
            throw ParseError("\(kind.capitalized) internal name cannot be '_'.")
        }

        _ = allowOmittedLocalName
        return (firstName, firstName)
    }

    mutating func parseAttributeIfPresent(before keyword: NeatSyntax.Keyword)
        -> AttributeApplication?
    {
        guard case .atAttribute = peek() else {
            return nil
        }

        guard peek(offset: 1) == .keyword(keyword.rawValue) else {
            return nil
        }

        let attribute = NeatSyntax.attributeApplication(for: peek())
        advance()
        return attribute
    }

    mutating func parseConformanceListIfPresent() throws -> [TypeReference] {
        guard peek() == .colon else {
            return []
        }

        try consume(.colon)
        var conformances: [TypeReference] = []

        while true {
            conformances.append(
                try parseNominalTypeReferenceNode(
                    expectedDescription: "Conformance"
                )
            )
            guard peek() == .comma else { break }
            advance()
        }

        return conformances
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

    mutating func skipGenericParameterClauseIfPresent() throws {
        guard peek() == .less else {
            return
        }

        var depth = 0
        while true {
            switch peek() {
            case .less:
                depth += 1
                advance()
            case .greater:
                depth -= 1
                advance()
                if depth == 0 {
                    return
                }
            case .eof:
                throw ParseError("Unterminated generic parameter clause.")
            default:
                advance()
            }
        }
    }

    mutating func skipMainBlockForDeclarationDiscovery() throws {
        guard case .hashDirective(let name) = peek(), name == "main" else {
            throw ParseError("Expected #main block.")
        }
        advance()
        try consume(.leftBrace)
        try skipUnknownBlockBody()
        try consume(.rightBrace)
    }



    mutating func skipStateDeclarationForDeclarationDiscovery() throws {
        _ = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.state)
        _ = try consumeIdentifier()
        if peek() == .colon {
            try consume(.colon)
            _ = try parseTypeReferenceNode()
        }
        if peek() == .equal {
            try consume(.equal)
            _ = try parseExpression()
        }
    }



    mutating func parseConstructDeclarationForDeclarationDiscovery() throws -> ConstructDeclaration {
        if isBuilderDeclarationStart() {
            try consume(.asterisk)
            guard case .identifier(let keyword) = peek(), keyword == "builder" else {
                throw ParseError("Expected declaration starting with '*builder'.")
            }
            advance()
            let name = try consumeTypeName()
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)

            return ConstructDeclaration(
                macros: [],
                kind: .builder,
                attribute: nil,
                name: name,
                genericParameters: [],
                conformances: [],
                states: [],
                environments: [],
                bindings: [],
                deriveds: [],
                values: [],
                initializers: [],
                callables: [],
                constructs: []
            )
        }

        let macros = try parseMacroApplicationsIfPresent()
        let attribute = parseAttributeIfPresent(before: .construct)
        let kind = try parseConstructKind(attribute: attribute)
        let header = try parseConstructHeader()
        var initializers: [InitializerDeclaration] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        if peek() == .leftBrace {
            try consume(.leftBrace)
            while peek() != .rightBrace {
                if isInitializerDeclarationStart() {
                    initializers.append(try parseInitializerDeclaration(signatureOnly: true))
                    continue
                }
                if isCallableStart() {
                    callables.append(try parseCallableDeclaration(signatureOnly: true))
                    continue
                }
                if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                    constructs.append(try parseConstructDeclarationForDeclarationDiscovery())
                    continue
                }
                if isStateDeclarationStart() {
                    try skipStateDeclarationForDeclarationDiscovery()
                    continue
                }
                if peek() == .leftBrace {
                    try consume(.leftBrace)
                    try skipUnknownBlockBody()
                    try consume(.rightBrace)
                    continue
                }
                advance()
            }
            try consume(.rightBrace)
        }

        return ConstructDeclaration(
            macros: macros,
            kind: kind,
            attribute: attribute,
            name: header.name,
            genericParameters: header.genericParameters,
            conformances: header.conformances,
            states: [],
            environments: [],
            bindings: [],
            deriveds: [],
            values: [],
            initializers: initializers,
            callables: callables,
            constructs: constructs
        )
    }



    mutating func skipConstructDeclarationForDeclarationDiscovery() throws {
        _ = try parseConstructDeclarationForDeclarationDiscovery()
    }


}
