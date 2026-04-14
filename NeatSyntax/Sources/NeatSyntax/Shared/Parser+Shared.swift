import Foundation

extension Parser {
    mutating func parseLabeledDeclarationName(
        expecting kind: String,
        allowOmittedLocalName: Bool = true
    ) throws -> (localName: String, externalLabel: String?) {
        let localName: String
        switch peek() {
        case .identifier(let value):
            localName = value
            advance()
        case .keyword(let value):
            localName = value
            advance()
        default:
            throw ParseError("Expected \(kind) name.")
        }
        if !allowOmittedLocalName, localName == "_" {
            throw ParseError("\(kind.capitalized) local name cannot be '_'.")
        }

        switch peek() {
        case .identifier(let secondName) where peek(offset: 1) == .colon:
            advance()
            return (localName, secondName == "_" ? nil : secondName)
        case .keyword(let secondName) where peek(offset: 1) == .colon:
            advance()
            return (localName, secondName == "_" ? nil : secondName)
        default:
            break
        }

        guard peek() == .colon else {
            throw ParseError("Expected ':' after \(kind) name.")
        }

        return (localName, localName)
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
            conformances.append(try parseTypeReferenceNode())
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
        guard case .atAttribute(let name, _) = peek(), name == "main" else {
            throw ParseError("Expected @main block.")
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
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
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
            initializers: [],
            callables: [],
            constructs: []
        )
    }



    mutating func skipConstructDeclarationForDeclarationDiscovery() throws {
        _ = try parseConstructDeclarationForDeclarationDiscovery()
    }


}
