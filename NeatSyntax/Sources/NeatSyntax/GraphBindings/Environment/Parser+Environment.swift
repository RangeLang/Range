import Foundation

extension Parser {
    mutating func parseEnvironmentDeclaration() throws -> EnvironmentDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.environment)
        let isStateAlias = peek() == .keyword(NeatSyntax.Keyword.state.rawValue)
        if isStateAlias {
            try consumeKeyword(.state)
        }
        let (localName, externalLabel) = try parseLabeledDeclarationName(expecting: "environment")
        try consume(.colon)
        let typeName = try consumeTypeReference()
        if peek() == .equal {
            throw ParseError(
                "Environment declarations do not take initializer expressions. Use the declared name to resolve from outer environment."
            )
        }
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return EnvironmentDeclaration(
            macros: macros,
            isState: isStateAlias,
            localName: localName,
            externalLabel: externalLabel,
            typeName: typeName
        )
    }

    func isEnvironmentDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        guard peek(offset: offset) == .keyword(NeatSyntax.Keyword.environment.rawValue) else {
            return false
        }
        let nameOffset: Int
        if peek(offset: offset + 1) == .keyword(NeatSyntax.Keyword.state.rawValue) {
            nameOffset = offset + 2
        } else {
            nameOffset = offset + 1
        }
        guard case .identifier = peek(offset: nameOffset) else { return false }
        if peek(offset: nameOffset + 1) == .colon {
            return true
        }
        return {
            guard case .identifier = peek(offset: nameOffset + 1) else { return false }
            return peek(offset: nameOffset + 2) == .colon
        }()
    }

    func isEnvironmentProvisionStart() -> Bool {
        guard peek() == .asterisk else { return false }
        return peek(offset: 1) == .keyword(NeatSyntax.Keyword.environment.rawValue)
    }

    mutating func parseEnvironmentProvision() throws -> EnvironmentProvision {
        try consume(.asterisk)
        try consumeKeyword(.environment)
        let isState = peek() == .keyword(NeatSyntax.Keyword.state.rawValue)
        if isState {
            try consumeKeyword(.state)
        }

        let name = try consumeIdentifier()
        try consume(.colon)
        let typeName = try consumeTypeReference()
        try consume(.equal)
        let expression = try parseExpression()

        return EnvironmentProvision(
            isState: isState,
            name: name,
            typeName: typeName,
            expression: expression
        )
    }
}
