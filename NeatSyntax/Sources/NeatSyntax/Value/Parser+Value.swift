import Foundation

extension Parser {
    mutating func parseValueDeclaration() throws -> ValueDeclaration {
        try consumeKeyword(.value)
        let (localName, externalLabel) = try parseLabeledDeclarationName(expecting: "value")
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
        return ValueDeclaration(
            localName: localName,
            externalLabel: externalLabel,
            typeName: typeName,
            value: value
        )
    }

    func isValueDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.value.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1) else { return false }
        if peek(offset: 2) == .colon {
            return true
        }
        return {
            guard case .identifier = peek(offset: 2) else { return false }
            return peek(offset: 3) == .colon
        }()
    }
}
