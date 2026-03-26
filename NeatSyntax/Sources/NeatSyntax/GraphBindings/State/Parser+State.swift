import Foundation

extension Parser {
    func isStateDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        return peek(offset: offset) == .keyword(NeatSyntax.Keyword.state.rawValue)
    }

    mutating func parseState(allowDeclaredStorage: Bool = false) throws -> StateDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.state)
        let name = try consumeIdentifier()
        var explicitType: TypeReference?
        if peek() == .colon {
            try consume(.colon)
            explicitType = try parseTypeReferenceNode()
        }
        let storage: StateStorage
        let inferredType: TypeReference

        if peek() == .equal {
            try consume(.equal)
            let initialValue = try parseExpression()
            if case .none = initialValue {
                guard let explicitType else {
                    throw ParseError(
                        "state '\(name)' initialized with none requires an explicit optional type.")
                }
                guard case .optional = explicitType else {
                    throw ParseError(
                        "state '\(name)' initialized with none requires an optional type.")
                }
                inferredType = explicitType
            } else {
                if let explicitType, case .call = initialValue {
                    inferredType = explicitType
                } else {
                    inferredType = .named(
                        try inferType(
                            of: initialValue,
                            accessibleTypes: accessibleBuiltinTypes()
                        ).displayName
                    )
                }
            }
            storage = .stored(initialValue)
        } else if allowDeclaredStorage, let explicitType {
            inferredType = explicitType
            storage = .declared
        } else {
            if allowDeclaredStorage {
                throw ParseError("state '\(name)' without initializer requires an explicit type.")
            }
            throw ParseError("state '\(name)' requires `= expression` outside construct storage.")
        }

        if let explicitType, !isCompatibleStateType(explicitType, inferredType: inferredType) {
            throw ParseError(
                "state '\(name)' expects \(explicitType.displayName), got \(inferredType.displayName)."
            )
        }
        return StateDeclaration(
            macros: macros,
            name: name,
            type: explicitType ?? inferredType,
            storage: storage
        )
    }

    func accessibleBuiltinTypes() -> [String: BuiltinType] {
        let builtinStateTypes = currentStateTypes.compactMapValues {
            builtinType(from: $0.displayName)
        }
        return builtinStateTypes.merging(currentEnvironmentTypes) { current, _ in current }
    }

    func isCompatibleStateType(_ explicitType: TypeReference, inferredType: TypeReference) -> Bool {
        if explicitType == inferredType {
            return true
        }

        if explicitType.displayName == "Float" && inferredType.displayName == "Double" {
            return true
        }

        return false
    }

    mutating func syncCurrentDeclarationSymbols(
        states: [StateDeclaration],
        environments: [EnvironmentDeclaration],
        bindings: [BindingDeclaration]
    ) {
        currentStateNames = Set(states.map(\.name))
        currentMutableStateNames = Set(states.map(\.name))
        currentEnvironmentNames = Set(environments.map(\.name))
        currentMutableEnvironmentNames = Set(environments.filter(\.isState).map(\.name))
        currentBindingNames = Set(bindings.map(\.name))
    }

    mutating func clearCurrentDeclarationSymbols() {
        currentStateNames = []
        currentMutableStateNames = []
        currentEnvironmentNames = []
        currentMutableEnvironmentNames = []
        currentBindingNames = []
    }
}
