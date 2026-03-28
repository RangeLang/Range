import Foundation

public enum BootstrapExpressionSemantics {
    public static func inferType(
        of expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType]
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
        case .array:
            throw ParseError("Array type inference is not supported in state initializers yet.")
        case .dictionary:
            throw ParseError(
                "Dictionary type inference is not supported in state initializers yet.")
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionType = try inferType(of: condition, accessibleTypes: accessibleTypes)
            guard isCompatible(actual: conditionType, expected: .named("Bool"), resolver: nil)
            else {
                throw ParseError(
                    "Ternary condition must be Bool, got \(conditionType.displayName).")
            }
            if isNilLiteral(trueExpression) {
                let falseType = try inferType(of: falseExpression, accessibleTypes: accessibleTypes)
                guard isOptionalExpressionType(falseType) else {
                    throw ParseError(
                        "Ternary branches must match, got nil and \(falseType.displayName)."
                    )
                }
                return falseType
            }
            if isNilLiteral(falseExpression) {
                let trueType = try inferType(of: trueExpression, accessibleTypes: accessibleTypes)
                guard isOptionalExpressionType(trueType) else {
                    throw ParseError(
                        "Ternary branches must match, got \(trueType.displayName) and nil."
                    )
                }
                return trueType
            }
            let trueType = try inferType(of: trueExpression, accessibleTypes: accessibleTypes)
            let falseType = try inferType(of: falseExpression, accessibleTypes: accessibleTypes)
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
        resolver: LiteralBridgeResolver?
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        default:
            if let resolver {
                return resolver.defaultDestinationType(for: type.displayName)
            }
            return BootstrapLiteralRegistry.bridge(for: type)?.defaultDestinationType
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
        resolver: LiteralBridgeResolver?
    ) -> Bool {
        switch actual {
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            if let resolver {
                return resolver.isCompatible(
                    expected: expected, carrierTypeName: actual.displayName)
            }
            guard let bridge = BootstrapLiteralRegistry.bridge(for: actual) else {
                return false
            }
            if bridge.requiresOptionalContext {
                if case .optional = expected {
                    return true
                }
                return false
            }
            return bridge.acceptedDestinationTypeNames.contains(expected.displayName)
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
        if expected.displayName == "Float" && actual.displayName == "Double" {
            return true
        }
        return false
    }

    public static func isNilLiteral(_ expression: Expression) -> Bool {
        if case .nilLiteral = expression { return true }
        return false
    }
}
