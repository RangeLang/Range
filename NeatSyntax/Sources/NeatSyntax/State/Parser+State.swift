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

    mutating func parseMemberDeclaration() throws -> MemberDeclaration {
        try consumeKeyword(.value)
        let (localName, externalLabel) = try parseLabeledDeclarationName(expecting: "value")
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let value: Expression?
        if peek() == .equal {
            try consume(.equal)
            value = try parseExpression()
        } else {
            value = nil
        }
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return MemberDeclaration(
            localName: localName,
            externalLabel: externalLabel,
            typeName: typeName,
            value: value
        )
    }

    mutating func parseBindingDeclaration() throws -> BindingDeclaration {
        try consumeKeyword(.binding)
        let (localName, externalLabel) = try parseLabeledDeclarationName(expecting: "binding")
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let storage: BindingStorage
        if peek() == .leftBrace {
            let previousBindingNames = currentBindingNames
            currentBindingNames = previousBindingNames.union([localName])
            storage = try parseDerivedBindingStorage(name: localName)
            currentBindingNames = previousBindingNames.union([localName])
        } else {
            storage = .plain
        }
        return BindingDeclaration(
            localName: localName,
            externalLabel: externalLabel,
            typeName: typeName,
            storage: storage
        )
    }

    mutating func parseEnvironmentDeclaration() throws -> EnvironmentDeclaration {
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
            isState: isStateAlias,
            localName: localName,
            externalLabel: externalLabel,
            typeName: typeName
        )
    }

    mutating func parseDerivedBindingStorage(name: String) throws -> BindingStorage {
        try consume(.leftBrace)

        var getterBody: [Statement]?
        var setterBody: [Statement]?

        while peek() != .rightBrace {
            if peek() == .keyword(NeatSyntax.Keyword.getter.rawValue) {
                guard getterBody == nil else {
                    throw ParseError("binding '\(name)' can only define one get block.")
                }
                try consumeKeyword(.getter)
                getterBody = try parseStatementBlock(baseLocalBindings: [:])
                continue
            }

            if peek() == .keyword(NeatSyntax.Keyword.setter.rawValue) {
                guard setterBody == nil else {
                    throw ParseError("binding '\(name)' can only define one set block.")
                }
                try consumeKeyword(.setter)
                setterBody = try parseStatementBlock(
                    baseLocalBindings: ["newValue": .constant]
                )
                continue
            }

            throw ParseError("Derived binding '\(name)' only supports get and set blocks.")
        }

        try consume(.rightBrace)

        guard let getterBody else {
            throw ParseError("Derived binding '\(name)' requires a get block.")
        }
        guard let setterBody else {
            throw ParseError("Derived binding '\(name)' requires a set block.")
        }

        return .derived(get: getterBody, set: setterBody)
    }

    func isMemberDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.value.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1) else { return false }
        if peek(offset: 2) == .colon {
            return true
        }
        return {
            guard case .identifier = peek(offset: 2) else { return false }
            return peek(offset: 3) == .colon
        }()
    }

    func isBindingDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.binding.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: 1) else { return false }
        if peek(offset: 2) == .colon {
            return true
        }
        return {
            guard case .identifier = peek(offset: 2) else { return false }
            return peek(offset: 3) == .colon
        }()
    }

    func isEnvironmentDeclarationStart() -> Bool {
        guard peek() == .keyword(NeatSyntax.Keyword.environment.rawValue) else {
            return false
        }
        let nameOffset: Int
        if peek(offset: 1) == .keyword(NeatSyntax.Keyword.state.rawValue) {
            nameOffset = 2
        } else {
            nameOffset = 1
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
}
