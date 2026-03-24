import Foundation

extension Parser {
    func isConstructDeclarationStart() -> Bool {
        switch peek() {
        case .keyword(NeatSyntax.Keyword.construct.rawValue):
            return true
        case .keyword(NeatSyntax.Keyword.primitive.rawValue):
            return peek(offset: 1) == .keyword(NeatSyntax.Keyword.construct.rawValue)
        case .atAttribute:
            return peek(offset: 1) == .keyword(NeatSyntax.Keyword.construct.rawValue)
                || (peek(offset: 1) == .keyword(NeatSyntax.Keyword.primitive.rawValue)
                    && peek(offset: 2) == .keyword(NeatSyntax.Keyword.construct.rawValue))
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

        let modifiers = parseTypeDefinitionModifiers(before: .construct)
        let attribute = modifiers.attribute
        let kind = try parseConstructKind(attribute: attribute)
        let header = try parseConstructHeader()
        let name = header.name
        let conformances = header.conformances
        let projectionTarget = header.projectionTarget

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
            currentStateTypes = outerStateTypes
            currentEnvironmentTypes = outerEnvironmentTypes
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
                    if let builtinType = builtinType(from: environment.typeName) {
                        currentEnvironmentTypes[environment.name] = builtinType
                    }
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

                let state = try parseState()
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
            clearCurrentDeclarationSymbols()

            try consume(.rightBrace)
        }

        if requiresEOF {
            try consume(.eof)
        }

        try validateCallableDeclarations(callables)
        try validateCallableReturnSemantics(callables)
        try validateDerivedDeclarations(deriveds)
        try validateInitializerDeclarations(initializers, availableDeriveds: deriveds)

        return ConstructDeclaration(
            kind: kind,
            attribute: attribute,
            primitive: modifiers.primitive,
            name: name,
            conformances: conformances,
            projectionTarget: projectionTarget,
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
            kind: .builder,
            attribute: nil,
            primitive: nil,
            name: name,
            conformances: [],
            projectionTarget: nil,
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

    mutating func parseConstructHeader() throws
        -> (name: String, conformances: [String], projectionTarget: String?)
    {
        let name = try consumeTypeName()

        if peek() == .colon || peek() == .keyword(NeatSyntax.Keyword.projection.rawValue)
            || peek() == .leftBrace
        {
            let projectionTarget = try parseProjectionTargetIfPresent()
            let conformances = try parseConformanceListIfPresent()
            return (name, conformances, projectionTarget)
        }

        throw ParseError(
            "Expected 'on', ':', or '{' after declaration name. Use construct \(name) { ... }, construct \(name): Contract { ... }, or construct \(name) on Target: Contract { ... }."
        )
    }
}
