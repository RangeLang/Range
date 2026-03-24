import Foundation

extension Parser {
    mutating func parseLabeledDeclarationName(
        expecting kind: String,
        allowOmittedLocalName: Bool = true
    ) throws -> (localName: String, externalLabel: String?) {
        let localName = try consumeIdentifier()
        if !allowOmittedLocalName, localName == "_" {
            throw ParseError("\(kind.capitalized) local name cannot be '_'.")
        }

        if case .identifier(let secondName) = peek(), peek(offset: 1) == .colon {
            advance()
            return (localName, secondName == "_" ? nil : secondName)
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
