import Foundation

extension Parser {
    func isProtocolDeclarationStart() -> Bool {
        switch peek() {
        case .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue):
            return true
        case .atAttribute:
            return peek(offset: 1) == .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue)
        default:
            return false
        }
    }

    public mutating func parseProtocolDeclaration(requiresEOF: Bool = true) throws
        -> ProtocolDeclaration
    {
        let attribute = parseAttributeIfPresent(before: .protocolDefinition)

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
            attribute: attribute,
            name: name,
            conformances: conformances
        )
    }
}
