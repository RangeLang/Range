import Foundation

extension Parser {
    mutating func parseValueDeclaration() throws -> ValueDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.let)
        let (localName, externalLabel) = try parseLabeledDeclarationName(expecting: "let")
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
        guard peek(offset: offset) == .keyword(NeatSyntax.Keyword.let.rawValue) else {
            return false
        }
        guard tokenCanStartDeclarationName(peek(offset: offset + 1)) else { return false }
        if peek(offset: offset + 2) == .colon {
            return true
        }
        return {
            guard tokenCanStartDeclarationName(peek(offset: offset + 2)) else { return false }
            return peek(offset: offset + 3) == .colon
        }()
    }

    private func tokenCanStartDeclarationName(_ token: Token) -> Bool {
        switch token {
        case .identifier, .keyword:
            return true
        default:
            return false
        }
    }
}
