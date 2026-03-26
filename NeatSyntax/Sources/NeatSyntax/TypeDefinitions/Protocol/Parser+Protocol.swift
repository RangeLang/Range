import Foundation

extension Parser {
    func isProtocolDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue):
            return true
        case .atAttribute:
            return peek(offset: offset + 1)
                == .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue)
        default:
            return false
        }
    }

    public mutating func parseProtocolDeclaration(requiresEOF: Bool = true) throws
        -> ProtocolDeclaration
    {
        let macros = try parseMacroApplicationsIfPresent()
        let attribute = parseAttributeIfPresent(before: .protocolDefinition)
        if attribute?.name == "core" {
            throw ParseError("@core can only be applied to construct declarations.")
        }

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
            attribute: attribute,
            name: name,
            conformances: conformances
        )
    }
}
