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
            inferredType = try inferInitializedBindingType(
                name: name,
                explicitType: explicitType,
                expression: initialValue,
                accessibleTypes: accessibleContextTypes(),
                bindingKindDescription: "state"
            )
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

    func inferInitializedBindingType(
        name: String,
        explicitType: TypeReference?,
        expression: Expression,
        accessibleTypes: [String: TypeReference],
        bindingKindDescription: String
    ) throws -> TypeReference {
        if isEmptyArrayLiteral(expression) {
            guard let explicitType else {
                throw ParseError(
                    "Array type inference requires at least one element."
                )
            }
            guard isExplicitBracketCollectionType(explicitType) else {
                throw ParseError(
                    "\(bindingKindDescription) '\(name)' initialized with [] requires an explicit array or set type."
                )
            }
            return explicitType
        }

        if isEmptyDictionaryLiteral(expression) {
            guard let explicitType else {
                throw ParseError(
                    "Dictionary type inference requires at least one element."
                )
            }
            guard isExplicitDictionaryType(explicitType) else {
                throw ParseError(
                    "\(bindingKindDescription) '\(name)' initialized with [:] requires an explicit dictionary type."
                )
            }
            return explicitType
        }

        if case .nilLiteral = expression {
            guard let explicitType else {
                throw ParseError(
                    "\(bindingKindDescription) '\(name)' initialized with nil requires an explicit optional type."
                )
            }
            guard case .optional = explicitType else {
                throw ParseError(
                    "\(bindingKindDescription) '\(name)' initialized with nil requires an optional type."
                )
            }
            return explicitType
        }

        if let explicitType {
            let bypassExplicitCompatibilityShortcut =
                bindingKindDescription == "value"
                && expressionProducesPromiseForValueJoin(expression)

            if !bypassExplicitCompatibilityShortcut,
                try BootstrapExpressionSemantics.isExpressionCompatible(
                    expression,
                    expected: explicitType,
                    accessibleTypes: accessibleTypes.mapValues(BootstrapLiteralType.typed),
                    callableReturnTypes: currentCallableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: literalBridgeResolver,
                    memberResolver: declarationMemberResolver,
                    operatorResolver: declarationOperatorResolver,
                    macroExpansionResolver: declarationMacroExpansionResolver
                )
            {
                return explicitType
            }
        }

        let rawInferred = try inferBootstrapExpressionType(
            of: expression,
            accessibleTypes: accessibleTypes
        )
        let inferred = settledBindingBootstrapTypeIfNeeded(
            rawInferred,
            bindingKindDescription: bindingKindDescription
        )

        if let explicitType {
            switch inferred {
            case .typed(let actualType):
                guard isCompatibleStateType(explicitType, inferredType: actualType) else {
                    throw ParseError(
                        "\(bindingKindDescription) '\(name)' expects \(explicitType.displayName), got \(actualType.displayName)."
                    )
                }
            default:
                break
            }
            return explicitType
        }

        guard let inferredReference = defaultDestinationTypeReference(for: inferred) else {
            throw ParseError(
                "\(bindingKindDescription) '\(name)' could not infer a destination type from \(inferred.displayName)."
            )
        }
        return inferredReference
    }

    func settledBindingBootstrapTypeIfNeeded(
        _ inferred: BootstrapLiteralType,
        bindingKindDescription: String
    ) -> BootstrapLiteralType {
        guard bindingKindDescription == "value" else {
            return inferred
        }

        guard case .typed(let typeReference) = inferred,
            let resultType = resultTypeForPromiseType(typeReference)
        else {
            return inferred
        }

        return .typed(resultType)
    }

    func expressionProducesPromiseForValueJoin(_ expression: Expression) -> Bool {
        guard case .call(let name, _) = expression,
            let returnType = currentCallableReturnTypes[name]
        else {
            return false
        }

        return resultTypeForPromiseType(returnType) != nil
    }

    func resultTypeForPromiseType(_ typeReference: TypeReference) -> TypeReference? {
        guard case .generic(let base, let arguments) = typeReference,
            arguments.count == 2
        else {
            return nil
        }

        guard case .named(let baseName) = base, baseName == "Promise" else {
            return nil
        }

        return .generic(base: .named("Result"), arguments: arguments)
    }

    func isEmptyArrayLiteral(_ expression: Expression) -> Bool {
        if case .array(let elements) = expression {
            return elements.isEmpty
        }
        return false
    }

    func isEmptyDictionaryLiteral(_ expression: Expression) -> Bool {
        if case .dictionary(let elements) = expression {
            return elements.isEmpty
        }
        return false
    }

    func isExplicitBracketCollectionType(_ typeReference: TypeReference) -> Bool {
        if case .array = typeReference {
            return true
        }
        guard case .generic(let base, let arguments) = typeReference else {
            return false
        }
        guard arguments.count == 1 else {
            return false
        }
        guard case .named(let baseName) = base else {
            return false
        }
        return baseName == "Set"
    }

    func isExplicitDictionaryType(_ typeReference: TypeReference) -> Bool {
        guard case .generic(let base, let arguments) = typeReference else {
            return false
        }
        guard arguments.count == 2 else {
            return false
        }
        guard case .named(let baseName) = base else {
            return false
        }
        return baseName == "Dictionary"
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
