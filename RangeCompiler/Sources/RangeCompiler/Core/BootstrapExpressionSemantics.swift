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
        case .macroInvocation(let name, let arguments):
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
            if arguments.isEmpty, name.first?.isUppercase == true {
                return .typed(.named("@\(name)"))
            }
            throw ParseError(
                "Expression macro @\(name) must be expanded before inference."
            )
        case .block:
            throw ParseError(
                "Block expressions are not supported in state initializer inference yet.")
        case .identifier(let name):
            if let type = accessibleTypes[name] {
                return type
            }
            if let metatype = inferMetatypeValue(named: name) {
                return .typed(metatype)
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
        case .call(let name, let arguments):
            if let returnType = callableReturnTypes[name] {
                return .typed(returnType)
            }
            if let memberType = inferKnownMemberCallType(
                name: name,
                arguments: arguments,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver
            ) {
                return .typed(memberType)
            }
            if let memberType = inferImplicitSelfMemberCallType(
                name: name,
                arguments: arguments,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver
            ) {
                return .typed(memberType)
            }
            if let constructorReturnType = inferGraphResolvedConstructCallReturnType(
                name: name,
                arguments: arguments,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver
            ) {
                return .typed(constructorReturnType)
            }
            if let constructorType = inferGraphResolvedConstructCallType(
                name: name,
                memberResolver: memberResolver
            ) {
                return .typed(constructorType)
            }
            if let enumCaseType = memberResolver.enumCaseReturnType(forCallName: name) {
                return .typed(enumCaseType)
            }
            throw ParseError(
                "Callable expression '\(name)' is not supported in state initializer inference yet."
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
                return try inferLogicalType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
            case .rangeUntil, .closedRange:
                return try inferResolvedBinaryOperatorType(
                    expression,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver
                )
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
        case .intLiteral:
            return .named("Int")
        case .floatLiteral:
            return .named("Float")
        case .stringLiteral:
            return .named("String")
        case .boolLiteral:
            return .named("Bool")
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
        resolver: LiteralBridgeResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver = .empty
    ) -> Bool {
        switch actual {
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            if case .optional(let wrapped) = expected {
                return isCompatible(
                    actual: actual,
                    expected: wrapped,
                    resolver: resolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
                )
            }
            if primitiveLiteralDestination(for: actual) == expected {
                return true
            }
            return resolver.isCompatible(
                expected: expected,
                carrierTypeName: actual.displayName
            )
        case .typed(let actualType):
            return actualType == expected
                || isCompatibleNamedType(expected: expected, actual: actualType)
                || typeCompatibilityResolver.isAssignable(actual: actualType, expected: expected)
        }
    }

    private static func primitiveLiteralDestination(for type: BootstrapLiteralType) -> TypeReference? {
        switch type {
        case .intLiteral:
            return .named("Int")
        case .floatLiteral:
            return .named("Float")
        case .stringLiteral:
            return .named("String")
        case .boolLiteral:
            return .named("Bool")
        default:
            return nil
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
        macroExpansionResolver: DeclarationMacroExpansionResolver = .empty,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver = .empty
    ) throws -> Bool {
        switch expression {
        case .macroInvocation:
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
                return isCompatible(
                    actual: inferred,
                    expected: expected,
                    resolver: resolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
                )
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
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
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
                return isCompatible(
                    actual: inferred,
                    expected: expected,
                    resolver: resolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
                )
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
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
                ) && isExpressionCompatible(
                    element.value,
                    expected: expectedValueType,
                    accessibleTypes: accessibleTypes,
                    callableReturnTypes: callableReturnTypes,
                    macroExpansionTypes: macroExpansionTypes,
                    resolver: resolver,
                    memberResolver: memberResolver,
                    operatorResolver: operatorResolver,
                    typeCompatibilityResolver: typeCompatibilityResolver
                )
            }
        case .call(let name, _):
            if enumCaseCallMatchesExpectedType(
                name: name,
                expression: expression,
                expected: expected,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            ) {
                return true
            }
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
            return isCompatible(
                actual: inferred,
                expected: expected,
                resolver: resolver,
                typeCompatibilityResolver: typeCompatibilityResolver
            )
        case .identifier(let name):
            if isLeadingDotMemberShorthand(name), canUseLeadingDotMemberShorthand(for: expected) {
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
            return isCompatible(
                actual: inferred,
                expected: expected,
                resolver: resolver,
                typeCompatibilityResolver: typeCompatibilityResolver
            )
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
            return isCompatible(
                actual: inferred,
                expected: expected,
                resolver: resolver,
                typeCompatibilityResolver: typeCompatibilityResolver
            )
        }
    }

    private static func isLeadingDotMemberShorthand(_ name: String) -> Bool {
        guard name.hasPrefix(".") else {
            return false
        }
        return name.count > 1
    }

    private static func canUseLeadingDotMemberShorthand(for expected: TypeReference) -> Bool {
        switch expected {
        case .named, .member, .generic:
            return true
        case .optional(let wrapped):
            return canUseLeadingDotMemberShorthand(for: wrapped)
        case .array, .function, .variadic:
            return false
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
        case .block, .macroInvocation, .identifier, .call, .bindingReference, .ternary, .unary,
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
        if let selfMemberName = name.strippingSelfMemberPrefix(),
            let memberType = inferKnownMemberIdentifierType(
                name: selfMemberName,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            )
        {
            return memberType
        }

        guard let (baseName, memberName, _) = splitMemberName(name),
            let baseReference = resolveMemberBaseType(
                baseName,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            )
        else {
            return nil
        }

        if baseReference.displayName == "Expression", memberName == "written" {
            return .named("WrittenSyntax")
        }

        if baseReference.displayName == "WrittenSyntax" {
            switch memberName {
            case "text":
                return .named("String")
            case "range":
                return .optional(.named("SourceRange"))
            default:
                break
            }
        }

        if let syntaxMemberType = inferKnownSyntaxMemberIdentifierType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return syntaxMemberType
        }

        if let memberType = memberResolver.memberType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return memberType
        }

        if let stringMemberType = inferKnownStringMemberIdentifierType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return stringMemberType
        }

        if let collectionMemberType = inferKnownCollectionMemberIdentifierType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return collectionMemberType
        }

        if baseName == "self",
            let type = accessibleTypes[memberName],
            case .typed(let reference) = type
        {
            return reference
        }

        return nil
    }

    private static func inferKnownMemberCallType(
        name: String,
        arguments: [CallArgument],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        if let selfMemberName = name.strippingSelfMemberPrefix(),
            let memberType = inferKnownMemberCallType(
                name: selfMemberName,
                arguments: arguments,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver
            )
        {
            return memberType
        }

        guard let (baseName, memberName, genericArguments) = splitMemberName(name),
            let baseReference = resolveMemberBaseType(
                baseName,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            )
        else {
            return nil
        }

        let typedArguments = arguments.map { argument in
            let inferred = try? inferType(
                of: argument.value,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver
            )
            return DeclarationMemberResolver.MemberCallArgument(
                label: argument.label,
                typeReference: inferred.flatMap {
                    defaultDestinationTypeReference(for: $0, resolver: resolver)
                }
            )
        }

        if let graphReturnType = memberResolver.memberCallableReturnType(
            baseType: baseReference,
            memberName: memberName,
            genericArguments: genericArguments,
            arguments: typedArguments
        ) {
            return graphReturnType
        }

        return inferKnownCollectionMemberCallType(
            baseType: baseReference,
            memberName: memberName
        )
    }

    private static func resolveMemberBaseType(
        _ name: String,
        accessibleTypes: [String: BootstrapLiteralType],
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        if let type = accessibleTypes[name],
            case .typed(let reference) = type
        {
            return reference
        }

        if let metatype = inferMetatypeValue(named: name) {
            return metatype
        }

        guard let (baseName, memberName, _) = splitMemberName(name),
            let baseReference = resolveMemberBaseType(
                baseName,
                accessibleTypes: accessibleTypes,
                memberResolver: memberResolver
            )
        else {
            return nil
        }

        if baseReference.displayName == "Expression", memberName == "written" {
            return .named("WrittenSyntax")
        }

        if baseReference.displayName == "WrittenSyntax" {
            switch memberName {
            case "text":
                return .named("String")
            case "range":
                return .optional(.named("SourceRange"))
            default:
                break
            }
        }

        if let syntaxMemberType = inferKnownSyntaxMemberIdentifierType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return syntaxMemberType
        }

        if let graphMemberType = memberResolver.memberType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return graphMemberType
        }

        if let stringMemberType = inferKnownStringMemberIdentifierType(
            baseType: baseReference,
            memberName: memberName
        ) {
            return stringMemberType
        }

        return inferKnownCollectionMemberIdentifierType(
            baseType: baseReference,
            memberName: memberName
        )
    }

    private static func inferKnownCollectionMemberCallType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        switch baseType {
        case .array(let element):
            switch memberName {
            case "map", "compactMap", "flatMap", "filter":
                return .array(element)
            case "forEach", "append", "update", "insert", "clear":
                return .named("Void")
            case "element", "remove":
                return element
            case "first", "last", "removeLast":
                return .optional(element)
            default:
                return nil
            }
        case .generic(let base, let arguments):
            guard case .named(let baseName) = base else {
                return nil
            }
            switch (baseName, memberName, arguments.count) {
            case ("String", "snakeCase", 0), ("String", "obfuscated", 0), ("String", "lastComponent", 0):
                return baseType
            case ("Array", "map", 1), ("Array", "compactMap", 1), ("Array", "flatMap", 1),
                ("Array", "filter", 1):
                return baseType
            case ("Array", "forEach", 1), ("Array", "append", 1), ("Array", "update", 1),
                ("Array", "insert", 1), ("Array", "clear", 1):
                return .named("Void")
            case ("Array", "element", 1), ("Array", "remove", 1):
                return arguments[0]
            case ("Array", "first", 1), ("Array", "last", 1), ("Array", "removeLast", 1):
                return .optional(arguments[0])
            case ("Dictionary", "value", 2), ("Dictionary", "removeValue", 2):
                return .optional(arguments[1])
            case ("Dictionary", "contains", 2):
                return .named("Bool")
            case ("Dictionary", "filter", 2):
                return .array(dictionaryEntryType(key: arguments[0], value: arguments[1]))
            case ("Dictionary", "first", 2):
                return .optional(dictionaryEntryType(key: arguments[0], value: arguments[1]))
            case ("Dictionary", "updateValue", 2), ("Dictionary", "clear", 2):
                return .named("Void")
            case ("Set", "contains", 1):
                return .named("Bool")
            case ("Set", "filter", 1):
                return .array(arguments[0])
            case ("Set", "first", 1):
                return .optional(arguments[0])
            case ("Set", "insert", 1), ("Set", "clear", 1):
                return .named("Void")
            case ("Set", "remove", 1):
                return .optional(arguments[0])
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func inferKnownCollectionMemberIdentifierType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        switch baseType {
        case .array:
            switch memberName {
            case "count":
                return .named("Int")
            case "isEmpty":
                return .named("Bool")
            default:
                return nil
            }
        case .generic(let base, let arguments):
            guard case .named(let baseName) = base else {
                return nil
            }
            switch (baseName, memberName, arguments.count) {
            case ("Array", "count", 1), ("Dictionary", "count", 2), ("Set", "count", 1):
                return .named("Int")
            case ("Array", "isEmpty", 1), ("Dictionary", "isEmpty", 2), ("Set", "isEmpty", 1):
                return .named("Bool")
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func inferKnownStringMemberIdentifierType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        guard case .named("String") = baseType else {
            return nil
        }
        switch memberName {
        case "count":
            return .named("Int")
        case "isEmpty":
            return .named("Bool")
        default:
            return nil
        }
    }

    private static func inferKnownSyntaxMemberIdentifierType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        switch (baseType.displayName, memberName) {
        case ("Construct", "declaration"):
            return .named("Construct.Declaration")
        case ("Construct.Declaration", "lets"):
            return .array(.named("Let"))
        case ("Construct.Declaration", "states"):
            return .array(.named("State"))
        case ("State", "type"), ("Let", "type"):
            return .named("TypeReference")
        default:
            return nil
        }
    }

    private static func inferImplicitSelfMemberCallType(
        name: String,
        arguments: [CallArgument],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        guard !name.contains("."),
            let selfType = accessibleTypes["self"],
            case .typed = selfType
        else {
            return nil
        }

        return inferKnownMemberCallType(
            name: "self.\(name)",
            arguments: arguments,
            accessibleTypes: accessibleTypes,
            callableReturnTypes: callableReturnTypes,
            macroExpansionTypes: macroExpansionTypes,
            resolver: resolver,
            memberResolver: memberResolver
        )
    }

    private static func inferMetatypeValue(named name: String) -> TypeReference? {
        guard name.hasSuffix(".self") else {
            return nil
        }
        let base = String(name.dropLast(".self".count))
        guard !base.isEmpty,
            let baseType = parseTypeReference(base)
        else {
            return nil
        }
        return .member(base: baseType, name: "Type")
    }

    private static func splitMemberName(_ name: String) -> (
        base: String,
        member: String,
        genericArguments: [TypeReference]
    )? {
        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }

        let base = String(name[..<dot])
        let rawMember = String(name[name.index(after: dot)...])
        let member = stripGenericArgumentClause(from: rawMember)
        guard !base.isEmpty, !member.isEmpty else {
            return nil
        }

        return (base, member, genericArguments(from: rawMember))
    }

    private static func stripGenericArgumentClause(from name: String) -> String {
        guard let genericStart = name.firstIndex(of: "<") else {
            return name
        }
        return String(name[..<genericStart])
    }

    private static func genericArguments(from name: String) -> [TypeReference] {
        guard let genericStart = name.firstIndex(of: "<"),
            name.hasSuffix(">")
        else {
            return []
        }
        let contentStart = name.index(after: genericStart)
        let contentEnd = name.index(before: name.endIndex)
        let content = String(name[contentStart..<contentEnd])
        return splitTopLevelTypeList(content).compactMap(parseTypeReference)
    }

    private static func splitTopLevelTypeList(_ source: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in source {
            switch character {
            case "<":
                depth += 1
                current.append(character)
            case ">":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty {
                    parts.append(part)
                }
                current = ""
            default:
                current.append(character)
            }
        }
        let finalPart = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalPart.isEmpty {
            parts.append(finalPart)
        }
        return parts
    }

    private static func parseTypeReference(_ source: String) -> TypeReference? {
        do {
            var parser = try Parser(source: source)
            let type = try parser.parseGenericArgumentReferenceNode()
            try parser.consume(.eof)
            return type
        } catch {
            return nil
        }
    }

    private static func inferGraphResolvedConstructCallType(
        name: String,
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        memberResolver.constructType(forConstructorCallName: name)
    }

    private static func inferGraphResolvedConstructCallReturnType(
        name: String,
        arguments: [CallArgument],
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver
    ) -> TypeReference? {
        let typedArguments = arguments.map { argument in
            let inferred = try? inferType(
                of: argument.value,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver
            )
            return DeclarationMemberResolver.MemberCallArgument(
                label: argument.label,
                typeReference: inferred.flatMap {
                    defaultDestinationTypeReference(for: $0, resolver: resolver)
                }
            )
        }

        return memberResolver.constructorCallReturnType(
            name: name,
            arguments: typedArguments
        )
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

    private static func enumCaseCallMatchesExpectedType(
        name: String,
        expression: Expression,
        expected: TypeReference,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) -> Bool {
        guard case .call(_, let arguments) = expression else {
            return false
        }

        let typedArguments = arguments.map { argument in
            let inferred = try? inferType(
                of: argument.value,
                accessibleTypes: accessibleTypes,
                callableReturnTypes: callableReturnTypes,
                macroExpansionTypes: macroExpansionTypes,
                resolver: resolver,
                memberResolver: memberResolver,
                operatorResolver: operatorResolver
            )
            return DeclarationMemberResolver.MemberCallArgument(
                label: argument.label,
                typeReference: inferred.flatMap {
                    defaultDestinationTypeReference(for: $0, resolver: resolver)
                }
            )
        }

        return memberResolver.enumCaseCallMatches(
            name: name,
            expected: expected,
            arguments: typedArguments
        )
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
        if let returnType = scalarEqualityReturnType(lhsType, rhsType, resolver: resolver) {
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
        if let returnType = scalarArithmeticReturnType(
            lhsType,
            rhsType,
            operatorSymbol: operatorSymbol,
            resolver: resolver
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
        if let returnType = scalarComparisonReturnType(lhsType, rhsType, resolver: resolver) {
            return .typed(returnType)
        }

        throw ParseError(
            "Operator '\(operatorSymbol.rawValue)' has no matching core signature for \(lhsType.displayName) and \(rhsType.displayName)."
        )
    }

    private static func inferLogicalType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, let operatorSymbol, let rhs) = expression,
            operatorSymbol == .and || operatorSymbol == .or
        else {
            throw ParseError("Expected logical expression.")
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

        if isCompatible(actual: lhsType, expected: .named("Bool"), resolver: resolver),
            isCompatible(actual: rhsType, expected: .named("Bool"), resolver: resolver)
        {
            return .typed(.named("Bool"))
        }

        throw ParseError(
            "Operator '\(operatorSymbol.rawValue)' requires Bool operands, got \(lhsType.displayName) and \(rhsType.displayName)."
        )
    }

    private static func inferResolvedBinaryOperatorType(
        _ expression: Expression,
        accessibleTypes: [String: BootstrapLiteralType],
        callableReturnTypes: [String: TypeReference],
        macroExpansionTypes: [String: TypeReference],
        resolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver
    ) throws -> BootstrapLiteralType {
        guard case .binary(let lhs, let operatorSymbol, let rhs) = expression else {
            throw ParseError("Expected binary expression.")
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

    private static func scalarEqualityReturnType(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        guard let lhsType = scalarMaterializedTypeReference(for: lhs, resolver: resolver),
            let rhsType = scalarMaterializedTypeReference(for: rhs, resolver: resolver)
        else {
            return nil
        }

        if scalarComparableTypesMatch(lhsType, rhsType) {
            return .named("Bool")
        }
        return nil
    }

    private static func scalarArithmeticReturnType(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType,
        operatorSymbol: BinaryOperator,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        guard let lhsType = scalarMaterializedTypeReference(for: lhs, resolver: resolver),
            let rhsType = scalarMaterializedTypeReference(for: rhs, resolver: resolver)
        else {
            return nil
        }

        if lhsType.displayName == "Int", rhsType.displayName == "Int" {
            return .named("Int")
        }
        if scalarNumericTypesMatch(lhsType, rhsType) {
            return .named("Float")
        }
        if operatorSymbol == .addition,
            lhsType.displayName == "String",
            rhsType.displayName == "String"
        {
            return .named("String")
        }
        return nil
    }

    private static func scalarComparisonReturnType(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        guard let lhsType = scalarMaterializedTypeReference(for: lhs, resolver: resolver),
            let rhsType = scalarMaterializedTypeReference(for: rhs, resolver: resolver)
        else {
            return nil
        }

        if lhsType.displayName == rhsType.displayName || scalarNumericTypesMatch(lhsType, rhsType) {
            return .named("Bool")
        }
        return nil
    }

    private static func scalarNumericTypesMatch(
        _ lhs: TypeReference,
        _ rhs: TypeReference
    ) -> Bool {
        let names = Set([lhs.displayName, rhs.displayName])
        return names.isSubset(of: ["Int", "Float"])
    }

    private static func scalarComparableTypesMatch(
        _ lhs: TypeReference,
        _ rhs: TypeReference
    ) -> Bool {
        if scalarNumericTypesMatch(lhs, rhs) {
            return true
        }
        return lhs.displayName == "String" && rhs.displayName == "String"
    }

    private static func scalarMaterializedTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        if let materialized = materializedTypeReference(for: type, resolver: resolver) {
            return materialized
        }

        switch type {
        case .intLiteral:
            return .named("Int")
        case .floatLiteral:
            return .named("Float")
        case .stringLiteral:
            return .named("String")
        case .boolLiteral:
            return .named("Bool")
        case .nilLiteral, .typed:
            return nil
        }
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

    private static func dictionaryEntryType(
        key: TypeReference,
        value: TypeReference
    ) -> TypeReference {
        .generic(base: .named("DictionaryEntry"), arguments: [key, value])
    }
}

private extension String {
    func strippingSelfMemberPrefix() -> String? {
        guard hasPrefix("self.") else {
            return nil
        }
        let stripped = dropFirst("self.".count)
        guard !stripped.isEmpty else {
            return nil
        }
        return String(stripped)
    }
}
