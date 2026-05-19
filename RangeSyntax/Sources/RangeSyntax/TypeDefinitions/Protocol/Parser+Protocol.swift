import Foundation

extension Parser {
    func isProtocolDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(RangeSyntax.Keyword.protocolDefinition.rawValue):
            return true
        case .atAttribute:
            return peek(offset: offset + 1)
                == .keyword(RangeSyntax.Keyword.protocolDefinition.rawValue)
        default:
            return false
        }
    }

    public mutating func parseProtocolDeclaration(requiresEOF: Bool = true) throws
        -> ProtocolDeclaration
    {
        let macros = try parseMacroApplicationsIfPresent()
        let attribute = parseAttributeIfPresent(before: .protocolDefinition)

        try consumeKeyword(.protocolDefinition)
        let name = try consumeTypeName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        let conformances = try parseConformanceListIfPresent()
        var states: [StateDeclaration] = []
        var bindings: [BindingDeclaration] = []
        var deriveds: [DerivedDeclaration] = []
        var values: [ValueDeclaration] = []
        var initializers: [InitializerDeclaration] = []
        var callables: [CallableDeclaration] = []

        if peek() == .leftBrace {
            try consume(.leftBrace)
            while peek() != .rightBrace {
                if isValueDeclarationStart() {
                    values.append(try parseValueDeclaration())
                    continue
                }
                if isBindingDeclarationStart() {
                    bindings.append(try parseBindingDeclaration())
                    continue
                }
                if isDerivedDeclarationStart() {
                    deriveds.append(try parseDerivedDeclaration())
                    continue
                }
                if isStateDeclarationStart() {
                    states.append(try parseState(allowDeclaredStorage: true))
                    continue
                }
                if isInitializerDeclarationStart() {
                    initializers.append(try parseInitializerDeclaration(signatureOnly: true))
                    continue
                }
                if isCallableStart() {
                    callables.append(try parseCallableDeclaration(signatureOnly: true))
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
            states: states,
            bindings: bindings,
            deriveds: deriveds,
            values: values,
            initializers: initializers,
            callables: callables
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
