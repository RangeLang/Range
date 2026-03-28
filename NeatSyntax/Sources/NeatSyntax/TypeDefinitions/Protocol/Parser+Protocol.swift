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
        let genericParameters = try parseProtocolGenericParameterClauseIfPresent()
        let conformances = try parseConformanceListIfPresent()
        var initializers: [InitializerDeclaration] = []

        if peek() == .leftBrace {
            try consume(.leftBrace)
            while peek() != .rightBrace {
                if isInitializerDeclarationStart() {
                    initializers.append(try parseInitializerDeclaration())
                    continue
                }
                try skipUnknownProtocolRequirement()
            }
            try consume(.rightBrace)
        }

        if requiresEOF {
            try consume(.eof)
        }

        return ProtocolDeclaration(
            macros: macros,
            attribute: attribute,
            name: name,
            genericParameters: genericParameters,
            conformances: conformances,
            initializers: initializers
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

    mutating func parseProtocolGenericParameterClauseIfPresent() throws -> [GenericParameter] {
        guard peek() == .less else {
            return []
        }

        try consume(.less)
        var parameters: [GenericParameter] = [try parseProtocolGenericParameter()]
        while peek() == .comma {
            advance()
            parameters.append(try parseProtocolGenericParameter())
        }
        try consume(.greater)
        return parameters
    }

    mutating func parseProtocolGenericParameter() throws -> GenericParameter {
        let name = try consumeIdentifier()
        let constraint: TypeReference?
        if peek() == .colon {
            try consume(.colon)
            constraint = try parseTypeReferenceNode()
        } else {
            constraint = nil
        }

        let defaultArgument: TypeReference?
        if peek() == .equal {
            try consume(.equal)
            defaultArgument = try parseTypeReferenceNode()
        } else {
            defaultArgument = nil
        }

        return .type(name: name, constraint: constraint, defaultArgument: defaultArgument)
    }
}
