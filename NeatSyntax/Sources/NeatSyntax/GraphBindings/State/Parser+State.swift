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
            if case .nilLiteral = initialValue {
                guard let explicitType else {
                    throw ParseError(
                        "state '\(name)' initialized with nil requires an explicit optional type.")
                }
                guard case .optional = explicitType else {
                    throw ParseError(
                        "state '\(name)' initialized with nil requires an optional type.")
                }
                inferredType = explicitType
            } else {
                let inferred = try inferBootstrapExpressionType(
                    of: initialValue,
                    accessibleTypes: accessibleContextTypes()
                )
                if let explicitType {
                    switch inferred {
                    case .typed(let actualType):
                        guard isCompatibleStateType(explicitType, inferredType: actualType) else {
                            throw ParseError(
                                "state '\(name)' expects \(explicitType.displayName), got \(actualType.displayName)."
                            )
                        }
                    default:
                        break
                    }
                    inferredType = explicitType
                } else {
                    guard let inferredReference = defaultDestinationTypeReference(for: inferred)
                    else {
                        throw ParseError(
                            "state '\(name)' could not infer a destination type from \(inferred.displayName)."
                        )
                    }
                    inferredType = inferredReference
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
        return StateDeclaration(
            macros: macros,
            name: name,
            hasExplicitTypeAnnotation: explicitType != nil,
            type: explicitType ?? inferredType,
            storage: storage
        )
    }

    func canUseExplicitTypeForStoredInitializer(_ expression: Expression) -> Bool {
        switch expression {
        case .call, .unary, .binary, .block:
            return true
        default:
            return false
        }
    }

    func accessibleContextTypes() -> [String: TypeReference] {
        currentStateTypes.merging(currentEnvironmentTypes) { current, _ in current }
    }

    func isCompatibleStateType(_ explicitType: TypeReference, inferredType: TypeReference) -> Bool {
        isCompatibleNamedType(expected: explicitType, actual: inferredType)
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
