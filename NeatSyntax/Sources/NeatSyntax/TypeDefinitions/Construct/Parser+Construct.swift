import Foundation

extension Parser {
    func isConstructDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(NeatSyntax.Keyword.construct.rawValue):
            return true
        case .atAttribute:
            return peek(offset: offset + 1) == .keyword(NeatSyntax.Keyword.construct.rawValue)
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

        var states: [StateDeclaration] = []
        var bindings: [BindingDeclaration] = []
        var deriveds: [DerivedDeclaration] = []
        var values: [ValueDeclaration] = []
        var initializers: [InitializerDeclaration] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []

        if peek() == .leftBrace {
            try consume(.leftBrace)

            let outerStateTypes = currentStateTypes
            let outerCallableReturnTypes = currentCallableReturnTypes
            let outerSelfAvailable = currentSelfAvailable
            let outerSelfType = currentSelfType
            currentStateTypes = outerStateTypes
            currentCallableReturnTypes = outerCallableReturnTypes
            currentSelfAvailable = true
            currentSelfType = .named(name)
            while isStateDeclarationStart()
                || isBindingDeclarationStart()
                || isDerivedDeclarationStart()
                || isValueDeclarationStart()
                || isInitializerDeclarationStart()
                || isCallableStart()
                || isConstructDeclarationStart()
            {
                syncCurrentDeclarationSymbols(
                    states: states,
                    bindings: bindings
                )
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
                if isInitializerDeclarationStart() {
                    initializers.append(try parseInitializerDeclaration())
                    continue
                }
                if isCallableStart() {
                    callables.append(try parseCallableDeclaration())
                    continue
                }
                if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                    constructs.append(try parseConstructDeclaration(requiresEOF: false))
                    continue
                }

                let state = try parseState(allowDeclaredStorage: true)
                states.append(state)
                currentStateTypes[state.name] = state.type
            }

            if peek() != .rightBrace {
                throw ParseError(
                    "Construct render bodies are no longer supported in NeatSyntax. Use declarations only."
                )
            }

            currentStateTypes = outerStateTypes
            currentCallableReturnTypes = outerCallableReturnTypes
            currentSelfAvailable = outerSelfAvailable
            currentSelfType = outerSelfType
            clearCurrentDeclarationSymbols()

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
        let name = try consumeTypeName()
        let genericParameters = try parseGenericParameterClauseIfPresent()

        if peek() == .colon || peek() == .leftBrace {
            let conformances = try parseConformanceListIfPresent()
            return (name, genericParameters, conformances)
        }

        throw ParseError(
            "Expected ':' or '{' after declaration name. Use construct \(name) { ... } or construct \(name): Contract { ... }."
        )
    }

}
