import Foundation

extension Parser {
    mutating func parseValueDeclaration() throws -> ValueDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
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
            macros: macros,
            localName: localName,
            externalLabel: externalLabel,
            typeName: typeName,
            value: value
        )
    }

    func isValueDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        guard peek(offset: offset) == .keyword(NeatSyntax.Keyword.value.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: offset + 1) else { return false }
        if peek(offset: offset + 2) == .colon {
            return true
        }
        return {
            guard case .identifier = peek(offset: offset + 2) else { return false }
            return peek(offset: offset + 3) == .colon
        }()
    }
}
