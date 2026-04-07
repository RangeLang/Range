import Foundation

public enum BootstrapExpressionSemantics {
    public static func inferType(
        of expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference] = [:],
        resolver: LiteralBridgeResolver
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
        case .block:
            throw ParseError(
                "Block expressions are not supported in state initializer inference yet.")
        case .identifier(let name):
            guard let type = accessibleTypes[name] else {
                throw ParseError("Unknown identifier '\(name)' in state initializer.")
            }
            return type
        case .call(let name, _):
            guard let returnType = callableReturnTypes[name] else {
                throw ParseError(
                    "Callable expressions are not supported in state initializer inference yet."
                )
            }
            return .typed(returnType)
        case .bindingReference(let name):
            throw ParseError("Binding reference '$\(name)' is not valid in a state initializer.")
        case .array(let elements):
            return try inferArrayType(
                elements: elements,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
            )
        case .dictionary(let elements):
            return try inferDictionaryType(
                elements: elements,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionType = try inferType(
                of: condition,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
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
                resolver: resolver
            )
            let falseType = try inferType(
                of: falseExpression,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
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
                    resolver: resolver
                )
            case .equal, .notEqual:
                return try inferEqualityType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    resolver: resolver
                )
            case .addition, .less, .lessEqual, .greater, .greaterEqual, .and, .or:
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
        resolver: LiteralBridgeResolver
    ) throws -> Bool {
        switch expression {
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
                    resolver: resolver
                )
                return isCompatible(actual: inferred, expected: expected, resolver: resolver)
            }

            return try elements.allSatisfy { element in
                try isExpressionCompatible(
                    element,
                    expected: expectedElementType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    resolver: resolver
                )
            }
        case .dictionary(let elements):
            guard let (expectedKeyType, expectedValueType) = expectedDictionaryTypes(expected)
            else {
                let inferred = try inferType(
                    of: expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    resolver: resolver
                )
                return isCompatible(actual: inferred, expected: expected, resolver: resolver)
            }

            return try elements.allSatisfy { element in
                try isExpressionCompatible(
                    element.key,
                    expected: expectedKeyType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    resolver: resolver
                ) && isExpressionCompatible(
                    element.value,
                    expected: expectedValueType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    resolver: resolver
                )
            }
        default:
            let inferred = try inferType(
                of: expression,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
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
        case .block, .identifier, .call, .bindingReference, .ternary, .unary, .binary:
            return false
        }
    }

    private static func inferArrayType(
        elements: [Expression],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver
    ) throws -> BootstrapLiteralType {
        guard let first = elements.first else {
            throw ParseError("Array type inference requires at least one element.")
        }

        var unified = try inferType(
            of: first,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            resolver: resolver
        )

        for element in elements.dropFirst() {
            let inferred = try inferType(
                of: element,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
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
        resolver: LiteralBridgeResolver
    ) throws -> BootstrapLiteralType {
        guard let first = elements.first else {
            throw ParseError("Dictionary type inference requires at least one element.")
        }

        var keyType = try inferType(
            of: first.key,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            resolver: resolver
        )
        var valueType = try inferType(
            of: first.value,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            resolver: resolver
        )

        for element in elements.dropFirst() {
            let inferredKey = try inferType(
                of: element.key,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
            )
            keyType = try unifyCollectionElementTypes(keyType, inferredKey, resolver: resolver)

            let inferredValue = try inferType(
                of: element.value,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                resolver: resolver
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

    private static func inferNilCoalescingType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, .nilCoalescing, let rhs) = expression else {
            throw ParseError("Expected nil-coalescing expression.")
        }

        let lhsType = try inferType(
            of: lhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            resolver: resolver
        )
        let rhsType = try inferType(
            of: rhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            resolver: resolver
        )

        if case .nilLiteral = lhsType {
            guard let rhsMaterialized = materializedTypeReference(for: rhsType, resolver: resolver)
            else {
                throw ParseError(
                    "Nil-coalescing fallback type could not be inferred from \(rhsType.displayName)."
                )
            }
            return .typed(rhsMaterialized)
        }

        guard let wrappedType = optionalWrappedType(for: lhsType) else {
            throw ParseError(
                "Left-hand side of ?? must be optional, got \(lhsType.displayName)."
            )
        }

        guard
            let rhsMaterialized = materializedTypeReference(for: rhsType, resolver: resolver),
            isCompatibleNamedType(expected: wrappedType, actual: rhsMaterialized)
        else {
            throw ParseError(
                "Nil-coalescing fallback must match \(wrappedType.displayName), got \(rhsType.displayName)."
            )
        }

        return .typed(wrappedType)
    }

    private static func inferEqualityType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver
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
            resolver: resolver
        )
        let rhsType = try inferType(
            of: rhs,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            resolver: resolver
        )

        guard equalityOperandsAreCompatible(lhsType, rhsType, resolver: resolver) else {
            throw ParseError(
                "Equality operands must be compatible, got \(lhsType.displayName) and \(rhsType.displayName)."
            )
        }

        return .typed(.named("Bool"))
    }

    private static func equalityOperandsAreCompatible(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> Bool {
        if case .nilLiteral = lhs {
            return isOptionalExpressionType(rhs)
        }
        if case .nilLiteral = rhs {
            return isOptionalExpressionType(lhs)
        }

        guard let lhsType = materializedTypeReference(for: lhs, resolver: resolver),
            let rhsType = materializedTypeReference(for: rhs, resolver: resolver)
        else {
            return false
        }

        return lhsType == rhsType
            || isCompatibleNamedType(expected: lhsType, actual: rhsType)
            || isCompatibleNamedType(expected: rhsType, actual: lhsType)
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
