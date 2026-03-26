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
}
