import Foundation

extension Parser {
    func isConstructDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(RangeSyntax.Keyword.construct.rawValue):
            return true
        case .macroAttribute:
            return peek(offset: offset + 1) == .keyword(RangeSyntax.Keyword.construct.rawValue)
        default:
            return false
        }
    }

    public mutating func parseConstructDeclaration(requiresEOF: Bool = true) throws
        -> ConstructDeclaration
    {
        if isBuilderDeclarationStart() {
            return try parseBuilderDeclaration(requiresEOF: requiresEOF)
        }

        let macros = try parseMacroApplicationsIfPresent()
        let attribute = parseAttributeIfPresent(before: .construct)
        let kind = try parseConstructKind(attribute: attribute)
        let header = try parseConstructHeader()
        let name = header.name
        let genericParameters = header.genericParameters
        let conformances = header.conformances

        let states: [StateDeclaration] = []
        let bindings: [BindingDeclaration] = []
        let deriveds: [DerivedDeclaration] = []
        let values: [ValueDeclaration] = []
        let initializers: [InitializerDeclaration] = []
        let callables: [CallableDeclaration] = []
        let constructs: [ConstructDeclaration] = []

        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }

        if requiresEOF {
            try consume(.eof)
        }

        try validateCallableDeclarations(callables)
        try validateDerivedDeclarations(deriveds)
        try validateInitializerDeclarations(
            initializers,
            availableDeriveds: deriveds,
            allowBodylessInitializers: declarationIsCore(attribute, macros: macros)
        )

        return ConstructDeclaration(
            macros: macros,
            kind: kind,
            attribute: attribute,
            name: name,
            genericParameters: genericParameters,
            conformances: conformances,
            states: states,
            bindings: bindings,
            deriveds: deriveds,
            values: values,
            initializers: initializers,
            callables: callables,
            constructs: constructs
        )
    }

    mutating func parseBuilderDeclaration(requiresEOF: Bool = true) throws -> ConstructDeclaration {
        try consume(.asterisk)
        guard case .identifier(let keyword) = peek(), keyword == "builder" else {
            throw ParseError("Expected declaration starting with '*builder'.")
        }
        advance()

        let name = try consumeTypeName()
        try consume(.leftBrace)

        var callables: [CallableDeclaration] = []
        while isBuilderCallableStart() {
            callables.append(try parseCallableDeclaration())
        }

        try consume(.rightBrace)
        if requiresEOF {
            try consume(.eof)
        }

        try validateCallableDeclarations(callables)

        return ConstructDeclaration(
            macros: [],
            kind: .builder,
            attribute: nil,
            name: name,
            genericParameters: [],
            conformances: [],
            states: [],
            bindings: [],
            deriveds: [],
            values: [],
            initializers: [],
            callables: callables,
            constructs: []
        )
    }

    mutating func parseConstructKind(attribute: AttributeApplication?) throws -> ConstructKind {
        switch peek() {
        case .identifier(let value) where value == "construct":
            advance()
        case .keyword(let value) where value == "construct":
            advance()
        default:
            throw ParseError("Expected declaration starting with 'construct'.")
        }

        if attribute?.name == "main" {
            return .entry
        }
        return .declaration
    }

    private func declarationIsCore(
        _ attribute: AttributeApplication?,
        macros: [MacroApplication]
    ) -> Bool {
        attribute?.isLanguageBoundary == true
            || macros.contains { $0.name == "language" || $0.name == "syntax" }
    }

    mutating func parseConstructHeader() throws
        -> (name: String, genericParameters: [GenericParameter], conformances: [TypeReference])
    {
        let name = try consumeQualifiedConstructName()
        let genericParameters = try parseGenericParameterClauseIfPresent()

        if peek() == .colon || peek() == .leftBrace {
            let conformances = try parseConformanceListIfPresent()
            return (name, genericParameters, conformances)
        }

        throw ParseError(
            "Expected ':' or '{' after declaration name. Use construct \(name) { ... } or construct \(name): Contract { ... }."
        )
    }

    mutating func consumeQualifiedConstructName() throws -> String {
        var components = [try consumeTypeName()]
        while peek() == .dot {
            try consume(.dot)
            components.append(try consumeTypeName())
        }
        return components.joined(separator: ".")
    }

}
