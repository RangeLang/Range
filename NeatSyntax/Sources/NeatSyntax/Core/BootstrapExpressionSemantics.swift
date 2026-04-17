import Foundation

public enum ExpressionTypeSemantics {
    public static func inferType(
        of expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference] = [:],
        macroExpansionTypes: [String: TypeReference] = [:],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver = .empty,
        operatorResolver: DeclarationOperatorResolver = .empty,
        macroExpansionResolver: DeclarationMacroExpansionResolver = .empty
    ) throws -> BootstrapLiteralType {
        switch expression {
        case .integer:
            return .intLiteral
        case .double:
            return .floatLiteral
        case .string, .interpolatedString:
            return .stringLiteral
        case .boolean:
            return .boolLiteral
        case .nilLiteral:
            return .nilLiteral
        case .freestandingMacro(let name, let arguments):
            if let expansionType = try inferMacroExpansionType(
                name: name,
                arguments: arguments,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                macroExpansionResolver: macroExpansionResolver
            ) {
                return .typed(expansionType)
            }
            throw ParseError(
                "Expression macro #\(name) must be expanded before inference."
            )
        case .block:
            throw ParseError(
                "Block expressions are not supported in state initializer inference yet.")
        case .identifier(let name):
            if let type = accessibleTypes[name] {
                return type
            }
            if let memberType = inferKnownMemberIdentifierType(
                name: name,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            ) {
                return .typed(memberType)
            }
            guard let type = accessibleTypes[name] else {
                throw ParseError("Unknown identifier '\(name)' in state initializer.")
            }
            return type
        case .call(let name, _):
            if let returnType = callableReturnTypes[name] {
                return .typed(returnType)
            }
            if let memberType = inferKnownMemberCallType(
                name: name,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            ) {
                return .typed(memberType)
            }
            if let constructorType = inferGraphResolvedConstructCallType(
                name: name,
                memberResolver: memberResolver
            ) {
                return .typed(constructorType)
            }
            throw ParseError(
                "Callable expressions are not supported in state initializer inference yet."
            )
        case .bindingReference(let name):
            if let type = accessibleTypes[name] {
                return type
            }
            if let memberType = inferKnownMemberIdentifierType(
                name: name,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            ) {
                return .typed(memberType)
            }
            throw ParseError("Binding reference '$\(name)' is not valid in a state initializer.")
        case .array(let elements):
            return try inferArrayType(
                elements: elements,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
        case .dictionary(let elements):
            return try inferDictionaryType(
                elements: elements,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionType = try inferType(
                of: condition,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            guard isCompatible(actual: conditionType, expected: .named("Bool"), resolver: resolver)
            else {
                throw ParseError(
                    "Ternary condition must be Bool, got \(conditionType.displayName).")
            }
            let trueType = try inferType(
                of: trueExpression,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            let falseType = try inferType(
                of: falseExpression,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            guard let unifiedType = unifyConditionalBranchTypes(
                trueType,
                falseType,
                resolver: resolver
            ) else {
                throw ParseError(
                    "Ternary branches must match, got \(trueType.displayName) and \(falseType.displayName)."
                )
            }
            return unifiedType
        case .unary(let operatorSymbol, _):
            switch operatorSymbol {
            case .not:
                throw ParseError(
                    "Unary operator typing is not supported by bootstrap inference yet.")
            }
        case .binary(_, let operatorSymbol, _):
            switch operatorSymbol {
            case .nilCoalescing:
                return try inferNilCoalescingType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            case .equal, .notEqual:
                return try inferEqualityType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            case .addition, .subtraction, .multiplication, .division, .remainder:
                return try inferArithmeticType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            case .less, .lessEqual, .greater, .greaterEqual:
                return try inferComparisonType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            case .and, .or:
                throw ParseError(
                    "Binary operator typing is not supported by bootstrap inference yet.")
            }
        }
    }

    public static func defaultDestinationTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        default:
            return resolver.defaultDestinationType(for: type.displayName)
        }
    }

    public static func isOptionalExpressionType(_ type: BootstrapLiteralType) -> Bool {
        switch type {
        case .nilLiteral:
            return true
        case .typed(let typeReference):
            if case .optional = typeReference {
                return true
            }
            return false
        default:
            return false
        }
    }

    public static func expressionTypesMatch(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType
    ) -> Bool {
        unifyConditionalBranchTypes(lhs, rhs, resolver: .empty) != nil
    }

    public static func isCompatible(
        actual: BootstrapLiteralType,
        expected: TypeReference,
        resolver: LiteralBridgeResolver
    ) -> Bool {
        switch actual {
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            if case .optional(let wrapped) = expected {
                return isCompatible(actual: actual, expected: wrapped, resolver: resolver)
            }
            return resolver.isCompatible(
                expected: expected,
                carrierTypeName: actual.displayName
            )
        case .typed(let actualType):
            return actualType == expected
                || isCompatibleNamedType(expected: expected, actual: actualType)
        }
    }

    public static func isExpressionCompatible(
        _ expression: Expression,
        expected: TypeReference,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference] = [:],
        macroExpansionTypes: [String: TypeReference] = [:],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver = .empty,
        operatorResolver: DeclarationOperatorResolver = .empty,
        macroExpansionResolver: DeclarationMacroExpansionResolver = .empty
    ) throws -> Bool {
        switch expression {
        case .freestandingMacro:
            // Expression-targeted macros expand before semantic validation. In an explicit
            // context, defer compatibility to the expanded expression instead of rejecting the
            // use site during bootstrap inference.
            return true
        case .nilLiteral:
            if case .optional = expected {
                return true
            }
            return false
        case .array(let elements):
            guard let expectedElementType = expectedBracketCollectionElementType(expected) else {
                let inferred = try inferType(
                    of: expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
                return isCompatible(actual: inferred, expected: expected, resolver: resolver)
            }

            return try elements.allSatisfy { element in
                try isExpressionCompatible(
                    element,
                    expected: expectedElementType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            }
        case .dictionary(let elements):
            guard let (expectedKeyType, expectedValueType) = expectedDictionaryTypes(expected)
            else {
                let inferred = try inferType(
                    of: expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
                return isCompatible(actual: inferred, expected: expected, resolver: resolver)
            }

            return try elements.allSatisfy { element in
                try isExpressionCompatible(
                    element.key,
                    expected: expectedKeyType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                ) && isExpressionCompatible(
                    element.value,
                    expected: expectedValueType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            }
        case .call(let name, _):
            if constructCallMatchesExpectedType(
                name: name,
                expected: expected,
                memberResolver: memberResolver
            ) {
                return true
            }
            let inferred = try inferType(
                of: expression,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            return isCompatible(actual: inferred, expected: expected, resolver: resolver)
        default:
            let inferred = try inferType(
                of: expression,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            return isCompatible(actual: inferred, expected: expected, resolver: resolver)
        }
    }

    public static func isCompatibleNamedType(expected: TypeReference, actual: TypeReference) -> Bool
    {
        if expected == actual {
            return true
        }

        switch (expected, actual) {
        case (.named(let expectedName), .named(let actualName)):
            if expectedName == "Float" && actualName == "Double" {
                return true
            }
            return false
        case (.optional(let expectedWrapped), .optional(let actualWrapped)):
            return isCompatibleNamedType(expected: expectedWrapped, actual: actualWrapped)
        case (.optional(let expectedWrapped), _):
            return isCompatibleNamedType(expected: expectedWrapped, actual: actual)
        case (.generic(let expectedBase, let expectedArguments), .array(let actualElement)):
            guard case .named(let expectedBaseName) = expectedBase,
                expectedBaseName == "Set",
                expectedArguments.count == 1
            else {
                return false
            }
            return isCompatibleNamedType(expected: expectedArguments[0], actual: actualElement)
        case (.array(let expectedElement), .array(let actualElement)):
            return isCompatibleNamedType(expected: expectedElement, actual: actualElement)
        case (.variadic(let expectedElement), .variadic(let actualElement)):
            return isCompatibleNamedType(expected: expectedElement, actual: actualElement)
        case (
            .generic(let expectedBase, let expectedArguments),
            .generic(let actualBase, let actualArguments)
        ):
            guard expectedArguments.count == actualArguments.count,
                isCompatibleNamedType(expected: expectedBase, actual: actualBase)
            else {
                return false
            }

            return zip(expectedArguments, actualArguments).allSatisfy {
                expectedArgument, actualArgument in
                isCompatibleNamedType(expected: expectedArgument, actual: actualArgument)
            }
        default:
            return false
        }
    }

    public static func isNilLiteral(_ expression: Expression) -> Bool {
        if case .nilLiteral = expression { return true }
        return false
    }

    public static func isLiteralExpression(_ expression: Expression) -> Bool {
        switch expression {
        case .integer, .double, .string, .interpolatedString, .boolean, .nilLiteral, .array,
            .dictionary:
            return true
        case .block, .freestandingMacro, .identifier, .call, .bindingReference, .ternary, .unary,
            .binary:
            return false
        }
    }

    private static func inferArrayType(
        elements: [Expression],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard let first = elements.first else {
            throw ParseError("Array type inference requires at least one element.")
        }

        var unified = try inferType(
            of: first,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )

        for element in elements.dropFirst() {
            let inferred = try inferType(
                of: element,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            unified = try unifyCollectionElementTypes(unified, inferred, resolver: resolver)
        }

        guard let elementType = materializedTypeReference(for: unified, resolver: resolver) else {
            throw ParseError(
                "Array literal element type could not be inferred from \(unified.displayName).")
        }

        return .typed(.array(elementType))
    }

    private static func inferDictionaryType(
        elements: [DictionaryElement],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard let first = elements.first else {
            throw ParseError("Dictionary type inference requires at least one element.")
        }

        var keyType = try inferType(
            of: first.key,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )
        var valueType = try inferType(
            of: first.value,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )

        for element in elements.dropFirst() {
            let inferredKey = try inferType(
                of: element.key,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            keyType = try unifyCollectionElementTypes(keyType, inferredKey, resolver: resolver)

            let inferredValue = try inferType(
                of: element.value,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            valueType = try unifyCollectionElementTypes(
                valueType, inferredValue, resolver: resolver)
        }

        guard let materializedKeyType = materializedTypeReference(for: keyType, resolver: resolver)
        else {
            throw ParseError(
                "Dictionary literal key type could not be inferred from \(keyType.displayName).")
        }
        guard
            let materializedValueType = materializedTypeReference(
                for: valueType,
                resolver: resolver
            )
        else {
            throw ParseError(
                "Dictionary literal value type could not be inferred from \(valueType.displayName)."
            )
        }

        return .typed(
            .generic(
                base: .named("Dictionary"),
                arguments: [materializedKeyType, materializedValueType]
            )
        )
    }

    private static func unifyCollectionElementTypes(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) throws -> BootstrapLiteralType {
        if expressionTypesMatch(lhs, rhs) {
            return lhs
        }

        guard let lhsType = materializedTypeReference(for: lhs, resolver: resolver),
            let rhsType = materializedTypeReference(for: rhs, resolver: resolver)
        else {
            throw ParseError(
                "Collection literal elements must share one type, got \(lhs.displayName) and \(rhs.displayName)."
            )
        }

        if isCompatibleNamedType(expected: lhsType, actual: rhsType) {
            return .typed(lhsType)
        }
        if isCompatibleNamedType(expected: rhsType, actual: lhsType) {
            return .typed(rhsType)
        }

        throw ParseError(
            "Collection literal elements must share one type, got \(lhs.displayName) and \(rhs.displayName)."
        )
    }

    private static func materializedTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        default:
            return defaultDestinationTypeReference(for: type, resolver: resolver)
        }
    }

    private static func inferMacroExpansionType(
        name: String,
        arguments: [CallArgument],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        macroExpansionResolver: DeclarationMacroExpansionResolver
    ) throws -> TypeReference? {
        if let expansionType = macroExpansionTypes[name], arguments.isEmpty {
            return expansionType
        }

        let typedArguments: [DeclarationMacroExpansionArgument] = arguments.map { argument in
            let inferred = try? inferType(
                of: argument.value,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver,
                macroExpansionResolver: macroExpansionResolver
            )
            return DeclarationMacroExpansionArgument(label: argument.label, type: inferred)
        }

        if let expansionType = macroExpansionResolver.expansionReturnType(
            name: name,
            arguments: typedArguments,
            literalBridgeResolver: resolver
        ) {
            return expansionType
        }

        return nil
    }

    private static func inferKnownMemberIdentifierType(
        name: String,
        accessibleTypes: [String: BootstrapLiteralType],
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        guard let (baseName, memberName) = splitMemberName(name),
            let baseType = accessibleTypes[baseName],
            case .typed(let baseReference) = baseType
        else {
            return nil
        }

        return memberResolver.memberType(baseType: baseReference, memberName: memberName)
    }

    private static func inferKnownMemberCallType(
        name: String,
        accessibleTypes: [String: BootstrapLiteralType],
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        guard let (baseName, memberName) = splitMemberName(name),
            let baseType = accessibleTypes[baseName],
            case .typed(let baseReference) = baseType
        else {
            return nil
        }

        return memberResolver.memberCallableReturnType(
            baseType: baseReference,
            memberName: memberName
        )
    }

    private static func splitMemberName(_ name: String) -> (base: String, member: String)? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let member = String(name[name.index(after: dot)...])
        guard !base.isEmpty, !member.isEmpty else {
            return nil
        }

        return (base, member)
    }

    private static func inferGraphResolvedConstructCallType(
        name: String,
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        memberResolver.constructType(forConstructorCallName: name)
    }

    private static func constructCallMatchesExpectedType(
        name: String,
        expected: TypeReference,
        memberResolver: DeclarationMemberResolver
    ) -> Bool {
        guard let actual = memberResolver.constructType(forConstructorCallName: name) else {
            return false
        }

        return isCompatibleNamedType(expected: expected, actual: actual)
    }

    private static func inferNilCoalescingType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, .nilCoalescing, let rhs) = expression else {
            throw ParseError("Expected nil-coalescing expression.")
        }

        let lhsType = try inferType(
            of: lhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )
        let rhsType = try inferType(
            of: rhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )

        if let returnType = operatorResolver.binaryOperatorReturnType(
            symbol: "??",
            lhs: lhsType,
            rhs: rhsType,
            literalBridgeResolver: resolver
        ) {
            return .typed(returnType)
        }

        throw ParseError(
            "Operator '??' has no matching core signature for \(lhsType.displayName) and \(rhsType.displayName)."
        )
    }

    private static func inferEqualityType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, let operatorSymbol, let rhs) = expression,
            operatorSymbol == .equal || operatorSymbol == .notEqual
        else {
            throw ParseError("Expected equality expression.")
        }

        let lhsType = try inferType(
            of: lhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )
        let rhsType = try inferType(
            of: rhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )

        if let returnType = operatorResolver.binaryOperatorReturnType(
            symbol: operatorSymbol.rawValue,
            lhs: lhsType,
            rhs: rhsType,
            literalBridgeResolver: resolver
        ) {
            return .typed(returnType)
        }

        throw ParseError(
            "Operator '\(operatorSymbol.rawValue)' has no matching core signature for \(lhsType.displayName) and \(rhsType.displayName)."
        )
    }

    private static func inferArithmeticType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, let operatorSymbol, let rhs) = expression,
            operatorSymbol == .addition || operatorSymbol == .subtraction
                || operatorSymbol == .multiplication || operatorSymbol == .division
                || operatorSymbol == .remainder
        else {
            throw ParseError("Expected arithmetic expression.")
        }

        let lhsType = try inferType(
            of: lhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )
        let rhsType = try inferType(
            of: rhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )

        if let returnType = operatorResolver.binaryOperatorReturnType(
            symbol: operatorSymbol.rawValue,
            lhs: lhsType,
            rhs: rhsType,
            literalBridgeResolver: resolver
        ) {
            return .typed(returnType)
        }

        throw ParseError(
            "Operator '\(operatorSymbol.rawValue)' has no matching core signature for \(lhsType.displayName) and \(rhsType.displayName)."
        )
    }

    private static func inferComparisonType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, let operatorSymbol, let rhs) = expression,
            operatorSymbol == .less || operatorSymbol == .lessEqual
                || operatorSymbol == .greater || operatorSymbol == .greaterEqual
        else {
            throw ParseError("Expected comparison expression.")
        }

        let lhsType = try inferType(
            of: lhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )
        let rhsType = try inferType(
            of: rhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver,
            operatorResolver: operatorResolver
        )

        if let returnType = operatorResolver.binaryOperatorReturnType(
            symbol: operatorSymbol.rawValue,
            lhs: lhsType,
            rhs: rhsType,
            literalBridgeResolver: resolver
        ) {
            return .typed(returnType)
        }

        throw ParseError(
            "Operator '\(operatorSymbol.rawValue)' has no matching core signature for \(lhsType.displayName) and \(rhsType.displayName)."
        )
    }

    private static func isStringCompatible(
        _ type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> Bool {
        if case .stringLiteral = type {
            return true
        }
        return isCompatible(actual: type, expected: .named("String"), resolver: resolver)
    }

    private static func unifyConditionalBranchTypes(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> BootstrapLiteralType? {
        switch (lhs, rhs) {
        case (.intLiteral, .intLiteral),
            (.floatLiteral, .floatLiteral),
            (.stringLiteral, .stringLiteral),
            (.boolLiteral, .boolLiteral),
            (.nilLiteral, .nilLiteral):
            return lhs
        case (.nilLiteral, _):
            guard let rhsType = materializedTypeReference(for: rhs, resolver: resolver) else {
                return nil
            }
            return .typed(.optional(rhsType))
        case (_, .nilLiteral):
            guard let lhsType = materializedTypeReference(for: lhs, resolver: resolver) else {
                return nil
            }
            return .typed(.optional(lhsType))
        case (.typed(let lhsType), .typed(let rhsType)):
            if lhsType == rhsType {
                return lhs
            }
            if isCompatibleNamedType(expected: lhsType, actual: rhsType) {
                return .typed(lhsType)
            }
            if isCompatibleNamedType(expected: rhsType, actual: lhsType) {
                return .typed(rhsType)
            }
            return nil
        default:
            guard let lhsType = materializedTypeReference(for: lhs, resolver: resolver),
                let rhsType = materializedTypeReference(for: rhs, resolver: resolver)
            else {
                return nil
            }

            if lhsType == rhsType {
                return .typed(lhsType)
            }
            if isCompatibleNamedType(expected: lhsType, actual: rhsType) {
                return .typed(lhsType)
            }
            if isCompatibleNamedType(expected: rhsType, actual: lhsType) {
                return .typed(rhsType)
            }
            return nil
        }
    }

    private static func optionalWrappedType(for type: BootstrapLiteralType) -> TypeReference? {
        switch type {
        case .nilLiteral:
            return nil
        case .typed(.optional(let wrapped)):
            return wrapped
        case .typed:
            return nil
        default:
            return nil
        }
    }

    private static func expectedBracketCollectionElementType(_ expected: TypeReference)
        -> TypeReference?
    {
        switch expected {
        case .array(let elementType):
            return elementType
        case .generic(let base, let arguments):
            guard case .named(let baseName) = base,
                baseName == "Set",
                arguments.count == 1
            else {
                return nil
            }
            return arguments[0]
        default:
            return nil
        }
    }

    private static func expectedDictionaryTypes(_ expected: TypeReference)
        -> (key: TypeReference, value: TypeReference)?
    {
        guard case .generic(let base, let arguments) = expected,
            case .named(let baseName) = base,
            baseName == "Dictionary",
            arguments.count == 2
        else {
            return nil
        }

        return (arguments[0], arguments[1])
    }
}
