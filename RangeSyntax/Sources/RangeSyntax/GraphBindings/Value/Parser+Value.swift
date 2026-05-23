import Foundation

extension Parser {
    mutating func parseValueDeclaration() throws -> ValueDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.let)
        let (localName, externalLabel) = try parseLabeledDeclarationName(expecting: "let")
        try consume(.colon)
        let annotation: (type: TypeReference, initializer: Expression?)?
        let value: Expression?
        let type: TypeReference
        if shouldParseTypedConstructionAfterColon() {
            annotation = try parseTypedConstructionAnnotation()
            type = annotation!.type
            value = annotation!.initializer
            if canStartInlineExpression() {
                throw ParseError(
                    "let '\(localName)' expects one initializer after ':'. Use typed construction, for example `let \(localName): \(type.displayName)(value)`."
                )
            }
        } else {
            annotation = nil
            value = try parseExpression()
            type = try inferInitializedBindingType(
                name: localName,
                explicitType: nil,
                expression: value!,
                accessibleTypes: accessibleContextTypes(),
                bindingKindDescription: "let"
            )
        }
        if peek() == .equal {
            throw ParseError(
                "let '\(localName)' expects declaration initialization after ':'. Use typed construction, for example `let \(localName): \(type.displayName)(value)`."
            )
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
            typeName: type.displayName,
            value: value
        )
    }

    func isValueDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        guard peek(offset: offset) == .keyword(RangeSyntax.Keyword.let.rawValue) else {
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
