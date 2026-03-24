import Foundation

extension Parser {
    func isPrimitiveModifierStart(before keyword: NeatSyntax.Keyword) -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.primitive.rawValue) else {
            return false
        }
        return peek(offset: 1) == .keyword(keyword.rawValue)
    }

    mutating func parseTypeDefinitionModifiers(before keyword: NeatSyntax.Keyword)
        -> (attribute: AttributeApplication?, primitive: PrimitiveModifier?)
    {
        let attribute: AttributeApplication?
        if case .atAttribute = peek(),
            peek(offset: 1) == .keyword(keyword.rawValue)
                || (peek(offset: 1) == .keyword(NeatSyntax.Keyword.primitive.rawValue)
                    && peek(offset: 2) == .keyword(keyword.rawValue))
        {
            attribute = NeatSyntax.attributeApplication(for: peek())
            advance()
        } else {
            attribute = nil
        }

        let primitive: PrimitiveModifier?
        if isPrimitiveModifierStart(before: keyword) {
            advance()
            primitive = PrimitiveModifier()
        } else {
            primitive = nil
        }

        return (attribute, primitive)
    }
}
