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
        var environments: [EnvironmentDeclaration] = []
        var bindings: [BindingDeclaration] = []
        var deriveds: [DerivedDeclaration] = []
        var values: [ValueDeclaration] = []
        var initializers: [InitializerDeclaration] = []
        var callables: [CallableDeclaration] = []

        if peek() == .leftBrace {
            try consume(.leftBrace)

            let outerStateTypes = currentStateTypes
            let outerEnvironmentTypes = currentEnvironmentTypes
            let outerCallableReturnTypes = currentCallableReturnTypes
            let outerSelfAvailable = currentSelfAvailable
            currentStateTypes = outerStateTypes
            currentEnvironmentTypes = outerEnvironmentTypes
            currentCallableReturnTypes = outerCallableReturnTypes
            currentSelfAvailable = true
            while peek() == .keyword(NeatSyntax.Keyword.state.rawValue)
                || isEnvironmentDeclarationStart()
                || isBindingDeclarationStart()
                || isDerivedDeclarationStart()
                || isValueDeclarationStart()
                || isInitializerDeclarationStart()
                || isCallableStart()
            {
                syncCurrentDeclarationSymbols(
                    states: states,
                    environments: environments,
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
                if isEnvironmentDeclarationStart() {
                    let environment = try parseEnvironmentDeclaration()
                    environments.append(environment)
                    currentEnvironmentTypes[environment.name] = environment.type
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
            currentEnvironmentTypes = outerEnvironmentTypes
            currentCallableReturnTypes = outerCallableReturnTypes
            currentSelfAvailable = outerSelfAvailable
            clearCurrentDeclarationSymbols()

            try consume(.rightBrace)
        }

        if requiresEOF {
            try consume(.eof)
        }

        try validateCallableDeclarations(callables)
        try validateCallableReturnSemantics(
            callables,
            allowBodylessCallables: declarationIsCore(attribute)
        )
        try validateDerivedDeclarations(deriveds)
        try validateInitializerDeclarations(
            initializers,
            availableDeriveds: deriveds,
            allowBodylessInitializers: declarationIsCore(attribute)
        )

        return ConstructDeclaration(
            macros: macros,
            kind: kind,
            attribute: attribute,
            name: name,
            genericParameters: genericParameters,
            conformances: conformances,
            states: states,
            environments: environments,
            bindings: bindings,
            deriveds: deriveds,
            values: values,
            initializers: initializers,
            callables: callables
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
        try validateCallableReturnSemantics(callables)

        return ConstructDeclaration(
            macros: [],
            kind: .builder,
            attribute: nil,
            name: name,
            genericParameters: [],
            conformances: [],
            states: [],
            environments: [],
            bindings: [],
            deriveds: [],
            values: [],
            initializers: [],
            callables: callables
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

    private func declarationIsCore(_ attribute: AttributeApplication?) -> Bool {
        attribute?.name == "core"
    }

    mutating func parseConstructHeader() throws
        -> (name: String, genericParameters: [GenericParameter], conformances: [TypeReference])
    {
        let name = try consumeTypeName()
        let genericParameters = try parseConstructGenericParameterClauseIfPresent()

        if peek() == .colon || peek() == .leftBrace {
            let conformances = try parseConformanceListIfPresent()
            return (name, genericParameters, conformances)
        }

        throw ParseError(
            "Expected ':' or '{' after declaration name. Use construct \(name) { ... } or construct \(name): Contract { ... }."
        )
    }

    mutating func parseConstructGenericParameterClauseIfPresent() throws -> [GenericParameter] {
        guard peek() == .less else {
            return []
        }

        try consume(.less)
        var parameters: [GenericParameter] = [try parseConstructGenericParameter()]
        while peek() == .comma {
            advance()
            parameters.append(try parseConstructGenericParameter())
        }
        try consume(.greater)
        return parameters
    }

    mutating func parseConstructGenericParameter() throws -> GenericParameter {
        if peek() == .keyword(NeatSyntax.Keyword.value.rawValue) {
            try consumeKeyword(.value)
            let name = try consumeIdentifier()
            try consume(.colon)
            let typeReference = try parseTypeReferenceNode()
            let defaultValue: Expression?
            if peek() == .equal {
                try consume(.equal)
                defaultValue = try parseExpression(terminatingAt: [.comma, .greater])
            } else {
                defaultValue = nil
            }
            return .value(name: name, typeReference: typeReference, defaultValue: defaultValue)
        }

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
