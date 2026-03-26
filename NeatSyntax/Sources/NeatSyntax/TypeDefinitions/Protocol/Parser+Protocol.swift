import Foundation

extension Parser {
    func isProtocolDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue):
            return true
        case .keyword(NeatSyntax.Keyword.primitive.rawValue):
            return peek(offset: offset + 1)
                == .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue)
        case .atAttribute:
            return peek(offset: offset + 1)
                == .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue)
                || (peek(offset: offset + 1) == .keyword(NeatSyntax.Keyword.primitive.rawValue)
                    && peek(offset: offset + 2)
                        == .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue))
        default:
            return false
        }
    }

    public mutating func parseProtocolDeclaration(requiresEOF: Bool = true) throws
        -> ProtocolDeclaration
    {
        let macros = try parseMacroApplicationsIfPresent()
        let modifiers = parseTypeDefinitionModifiers(before: .protocolDefinition)

        try consumeKeyword(.protocolDefinition)
        let name = try consumeTypeName()
        let conformances = try parseConformanceListIfPresent()

        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }

        if requiresEOF {
            try consume(.eof)
        }

        return ProtocolDeclaration(
            macros: macros,
            attribute: modifiers.attribute,
            primitive: modifiers.primitive,
            name: name,
            conformances: conformances
        )
    }
}
