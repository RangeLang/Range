import Foundation

extension Parser {
    func isStateDeclarationStart() -> Bool {
        let offset = macroApplicationLookaheadLength(excluding: ["state"])
        guard case .macroAttribute(let name, _) = peek(offset: offset), name == "state" else {
            return false
        }
        return tokenCanStartStateName(peek(offset: offset + 1))
    }

    mutating func parseState(allowDeclaredStorage: Bool = false) throws -> StateDeclaration {
        let macros = try parseMacroApplicationsIfPresent(excluding: ["state"])
        try consumeMacroAttribute(named: "state")
        let name = try consumeIdentifier()
        var explicitType: TypeReference?
        var typedInitializer: Expression?
        if peek() == .colon {
            try consume(.colon)
            if shouldParseTypedConstructionAfterColon() {
                let annotation = try parseTypedConstructionAnnotation()
                explicitType = annotation.type
                typedInitializer = annotation.initializer
                if canStartInlineExpression() {
                    throw ParseError(
                        "state '\(name)' expects one initializer after ':'. Use typed construction, for example `state \(name): \(annotation.type.displayName)(value)`."
                    )
                }
            } else {
                typedInitializer = try parseExpression()
            }
        }
        let storage: StateStorage
        let inferredType: TypeReference

        if peek() == .equal {
            throw ParseError(
                "state '\(name)' expects declaration initialization after ':'. Use typed construction, for example `state \(name): Type(value)`."
            )
        } else if explicitType != nil, canStartInlineExpression() {
            throw ParseError(
                "state '\(name)' expects one initializer after ':'. Use typed construction, for example `state \(name): \(explicitType!.displayName)(value)`."
            )
        } else if let typedInitializer {
            inferredType = try inferInitializedBindingType(
                name: name,
                explicitType: explicitType,
                expression: typedInitializer,
                accessibleTypes: accessibleContextTypes(),
                bindingKindDescription: "state",
                allowPromiseResolution: false
            )
            storage = .stored(typedInitializer)
        } else if allowDeclaredStorage, let explicitType {
            inferredType = explicitType
            storage = .declared
        } else {
            if allowDeclaredStorage {
                throw ParseError("state '\(name)' without initializer requires an explicit type.")
            }
            throw ParseError("state '\(name)' requires typed construction outside construct storage.")
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

    private func tokenCanStartStateName(_ token: Token) -> Bool {
        switch token {
        case .identifier, .keyword:
            return true
        default:
            return false
        }
    }

    func accessibleContextTypes() -> [String: TypeReference] {
        var types = currentStateTypes
        if let currentSelfType {
            types["self"] = currentSelfType
        }
        return types
    }

    func isCompatibleStateType(_ explicitType: TypeReference, inferredType: TypeReference) -> Bool {
        isCompatibleNamedType(expected: explicitType, actual: inferredType)
    }

    func inferInitializedBindingType(
        name: String,
        explicitType: TypeReference?,
        expression: Expression,
        accessibleTypes: [String: TypeReference],
        bindingKindDescription: String,
        allowPromiseResolution: Bool = false
    ) throws -> TypeReference {
        if currentMacroBodyDepth > 0, let explicitType {
            return explicitType
        }

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

        if let explicitType, isCollectionLiteral(expression) {
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

        if let explicitType,
            (try? ExpressionTypeSemantics.isExpressionCompatible(
                expression,
                expected: explicitType,
                accessibleTypes: accessibleTypes.mapValues(BootstrapLiteralType.typed),
                callableReturnTypes: currentCallableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: literalBridgeResolver,
                memberResolver: declarationMemberResolver,
                operatorResolver: declarationOperatorResolver,
                macroExpansionResolver: declarationMacroExpansionResolver
            )) == true
        {
            return explicitType
        }

        if let explicitType,
            case .call = expression
        {
            return explicitType
        }

        let inferred = try inferExpressionType(
            of: expression,
            accessibleTypes: accessibleTypes
        )

        if let explicitType {
            switch inferred {
            case .typed(let actualType):
                if allowPromiseResolution,
                    let successType = unwrappedPromiseSuccessType(actualType),
                    isCompatibleStateType(explicitType, inferredType: successType)
                {
                    return explicitType
                }
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
        if allowPromiseResolution, let successType = unwrappedPromiseSuccessType(inferredReference) {
            return successType
        }
        return inferredReference
    }

    func unwrappedPromiseSuccessType(_ typeReference: TypeReference) -> TypeReference? {
        guard
            case .generic(let base, let arguments) = typeReference,
            case .named(let baseName) = base,
            baseName == "Promise",
            arguments.count == 2
        else {
            return nil
        }

        return arguments[0]
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

    func isCollectionLiteral(_ expression: Expression) -> Bool {
        switch expression {
        case .array, .dictionary:
            return true
        default:
            return false
        }
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
        bindings: [BindingDeclaration]
    ) {
        currentStateNames = Set(states.map(\.name))
        currentMutableStateNames = Set(states.map(\.name))
        currentBindingNames = Set(bindings.map(\.name))
    }

    mutating func clearCurrentDeclarationSymbols() {
        currentStateNames = []
        currentMutableStateNames = []
        currentBindingNames = []
    }
}
