import Foundation

extension Parser {
    mutating func parseValueDeclaration() throws -> ValueDeclaration {
        let macros = try parseMacroApplicationsIfPresent(excluding: ["let"])
        try consumeMacroAttribute(named: "let")
        let name = try parseDeclarationName(expecting: "let")
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
                    "let '\(name)' expects one initializer after ':'. Use typed construction, for example `let \(name): \(type.displayName)(value)`."
                )
            }
        } else {
            annotation = nil
            value = try parseExpression()
            type = try inferInitializedBindingType(
                name: name,
                explicitType: nil,
                expression: value!,
                accessibleTypes: accessibleContextTypes(),
                bindingKindDescription: "let"
            )
        }
        if peek() == .equal {
            throw ParseError(
                "let '\(name)' expects declaration initialization after ':'. Use typed construction, for example `let \(name): \(type.displayName)(value)`."
            )
        }
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return ValueDeclaration(
            macros: macros,
            name: name,
            typeName: type.displayName,
            value: value
        )
    }

    func isValueDeclarationStart() -> Bool {
        let offset = macroApplicationLookaheadLength(excluding: ["let"])
        guard case .macroAttribute(let name, _) = peek(offset: offset), name == "let" else {
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

    private mutating func consumeMacroAttribute(named expectedName: String) throws {
        guard case .macroAttribute(let name, nil) = peek(), name == expectedName else {
            throw ParseError("Expected @\(expectedName).")
        }
        advance()
    }
}
