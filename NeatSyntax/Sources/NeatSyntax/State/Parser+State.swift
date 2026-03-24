import Foundation

extension Parser {
    mutating func parseState() throws -> StateDeclaration {
        try consumeKeyword(.state)
        let name = try consumeIdentifier()
        var explicitType: BuiltinType?
        if peek() == .colon {
            try consume(.colon)
            explicitType = try parseBuiltinType()
        }
        let storage: StateStorage
        let inferredType: BuiltinType

        if peek() == .equal {
            try consume(.equal)
            let initialValue = try parseExpression()
            if case .none = initialValue {
                guard let explicitType else {
                    throw ParseError(
                        "state '\(name)' initialized with none requires an explicit optional type.")
                }
                guard explicitType.isOptional else {
                    throw ParseError(
                        "state '\(name)' initialized with none requires an optional type.")
                }
                inferredType = explicitType
            } else {
                if let explicitType, case .call = initialValue {
                    inferredType = explicitType
                } else {
                    inferredType = try inferType(
                        of: initialValue,
                        accessibleTypes: accessibleBuiltinTypes()
                    )
                }
            }
            storage = .stored(initialValue)
        } else {
            throw ParseError("state '\(name)' requires `= expression`.")
        }

        if let explicitType, !isCompatibleStateType(explicitType, inferredType: inferredType) {
            throw ParseError(
                "state '\(name)' expects \(explicitType.displayName), got \(inferredType.displayName)."
            )
        }
        return StateDeclaration(
            name: name, type: explicitType ?? inferredType, storage: storage)
    }

    func accessibleBuiltinTypes() -> [String: BuiltinType] {
        currentStateTypes.merging(currentEnvironmentTypes) { current, _ in current }
    }

    func isCompatibleStateType(_ explicitType: BuiltinType, inferredType: BuiltinType) -> Bool {
        if explicitType == inferredType {
            return true
        }

        if explicitType == .float && inferredType == .double {
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
        currentMutableStateNames = Set(
            states.compactMap { state in
                if case .stored = state.storage { return state.name }
                return nil
            })
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
