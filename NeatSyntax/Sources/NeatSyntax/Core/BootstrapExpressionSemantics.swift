import Foundation

public enum BootstrapExpressionSemantics {
    public static func inferType(
        of expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
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
        case .call:
            throw ParseError(
                "Callable expressions are not supported in state initializer inference yet.")
        case .bindingReference(let name):
            throw ParseError("Binding reference '$\(name)' is not valid in a state initializer.")
        case .array(let elements):
            return try inferArrayType(
                elements: elements,
                accessibleTypes: accessibleTypes,
                resolver: resolver
            )
        case .dictionary(let elements):
            return try inferDictionaryType(
                elements: elements,
                accessibleTypes: accessibleTypes,
                resolver: resolver
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionType = try inferType(
                of: condition,
                accessibleTypes: accessibleTypes,
                resolver: resolver
            )
            guard isCompatible(actual: conditionType, expected: .named("Bool"), resolver: resolver)
            else {
                throw ParseError(
                    "Ternary condition must be Bool, got \(conditionType.displayName).")
            }
            if isNilLiteral(trueExpression) {
                let falseType = try inferType(
                    of: falseExpression,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver
                )
                guard isOptionalExpressionType(falseType) else {
                    throw ParseError(
                        "Ternary branches must match, got nil and \(falseType.displayName)."
                    )
                }
                return falseType
            }
            if isNilLiteral(falseExpression) {
                let trueType = try inferType(
                    of: trueExpression,
                    accessibleTypes: accessibleTypes,
                    resolver: resolver
                )
                guard isOptionalExpressionType(trueType) else {
                    throw ParseError(
                        "Ternary branches must match, got \(trueType.displayName) and nil."
                    )
                }
                return trueType
            }
            let trueType = try inferType(
                of: trueExpression,
                accessibleTypes: accessibleTypes,
                resolver: resolver
            )
            let falseType = try inferType(
                of: falseExpression,
                accessibleTypes: accessibleTypes,
                resolver: resolver
            )
            guard expressionTypesMatch(trueType, falseType) else {
                throw ParseError(
                    "Ternary branches must match, got \(trueType.displayName) and \(falseType.displayName)."
                )
            }
            return trueType
        case .unary(let operatorSymbol, _):
            switch operatorSymbol {
            case .not:
                throw ParseError(
                    "Unary operator typing is not supported by bootstrap inference yet.")
            }
        case .binary(_, let operatorSymbol, _):
            switch operatorSymbol {
            case .addition, .nilCoalescing, .equal, .notEqual, .less, .lessEqual, .greater,
                .greaterEqual, .and, .or:
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
        switch (lhs, rhs) {
        case (.intLiteral, .intLiteral),
            (.floatLiteral, .floatLiteral),
            (.stringLiteral, .stringLiteral),
            (.boolLiteral, .boolLiteral),
            (.nilLiteral, .nilLiteral):
            return true
        case (.typed(let lhsType), .typed(let rhsType)):
            return lhsType == rhsType || isCompatibleNamedType(expected: lhsType, actual: rhsType)
        default:
            return false
        }
    }

    public static func isCompatible(
        actual: BootstrapLiteralType,
        expected: TypeReference,
        resolver: LiteralBridgeResolver
    ) -> Bool {
        switch actual {
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            return resolver.isCompatible(
                expected: expected,
                carrierTypeName: actual.displayName
            )
        case .typed(let actualType):
            return actualType == expected
                || isCompatibleNamedType(expected: expected, actual: actualType)
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
        case (.optional(let expectedWrapped), .optional(let actualWrapped)):
            return isCompatibleNamedType(expected: expectedWrapped, actual: actualWrapped)
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
        resolver: LiteralBridgeResolver
    ) throws -> BootstrapLiteralType {
        guard let first = elements.first else {
            throw ParseError("Array type inference requires at least one element.")
        }

        var unified = try inferType(
            of: first,
            accessibleTypes: accessibleTypes,
            resolver: resolver
        )

        for element in elements.dropFirst() {
            let inferred = try inferType(
                of: element,
                accessibleTypes: accessibleTypes,
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
        resolver: LiteralBridgeResolver
    ) throws -> BootstrapLiteralType {
        guard let first = elements.first else {
            throw ParseError("Dictionary type inference requires at least one element.")
        }

        var keyType = try inferType(
            of: first.key,
            accessibleTypes: accessibleTypes,
            resolver: resolver
        )
        var valueType = try inferType(
            of: first.value,
            accessibleTypes: accessibleTypes,
            resolver: resolver
        )

        for element in elements.dropFirst() {
            let inferredKey = try inferType(
                of: element.key,
                accessibleTypes: accessibleTypes,
                resolver: resolver
            )
            keyType = try unifyCollectionElementTypes(keyType, inferredKey, resolver: resolver)

            let inferredValue = try inferType(
                of: element.value,
                accessibleTypes: accessibleTypes,
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
}
