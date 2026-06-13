import Foundation

extension Parser {
    func isProtocolDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(RangeSyntax.Keyword.protocolDefinition.rawValue):
            return true
        case .macroAttribute:
            return peek(offset: offset + 1)
                == .keyword(RangeSyntax.Keyword.protocolDefinition.rawValue)
        default:
            return false
        }
    }

    public mutating func parseProtocolDeclaration(requiresEOF: Bool = true) throws
        -> ProtocolDeclaration
    {
        throw ParseError(
            "Protocol declarations are no longer supported. Use macro graph metadata instead."
        )
    }

    mutating func skipUnknownProtocolRequirement() throws {
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
            return
        }

        while peek() != .rightBrace, peek() != .eof {
            advance()
        }
    }
}
