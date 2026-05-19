import Foundation

public struct DeclarationMacroExpansionArgument: Sendable {
    public let label: String?
    public let type: BootstrapLiteralType?

    public init(label: String?, type: BootstrapLiteralType?) {
        self.label = label
        self.type = type
    }
}

public struct DeclarationMacroExpansionResolver: Sendable {
    public static let empty = DeclarationMacroExpansionResolver(macrosByName: [:])

    private struct MacroExpansionParameter: Sendable {
        var localName: String
        var externalLabel: String?
        var typeReference: TypeReference?
        var isBinding: Bool
        var capturesSyntax: Bool
    }

    private struct MacroExpansionSignature: Sendable {
        var genericParameterNames: Set<String>
        var parameters: [MacroExpansionParameter]
        var returnType: TypeReference
    }

    private let signaturesByName: [String: [MacroExpansionSignature]]

    public init(macrosByName: [String: MacroDeclaration]) {
        self.signaturesByName = macrosByName.mapValues { macro in
            guard let expansionType = macro.expansionType else {
                return []
            }
            return [
                MacroExpansionSignature(
                    genericParameterNames: Set(macro.genericParameters.map(Self.genericParameterName)),
                    parameters: macro.parameters.map {
                        MacroExpansionParameter(
                            localName: $0.localName,
                            externalLabel: $0.externalLabel,
                            typeReference: $0.typeReference,
                            isBinding: $0.isBinding,
                            capturesSyntax: $0.capturesSyntax
                        )
                    },
                    returnType: expansionType
                )
            ]
        }
    }

    public func expansionReturnType(
        name: String,
        arguments: [DeclarationMacroExpansionArgument],
        literalBridgeResolver: LiteralBridgeResolver
    ) -> TypeReference? {
        let matches: [TypeReference] = signaturesByName[name, default: []].compactMap { signature in
            guard signature.parameters.count == arguments.count else {
                return nil
            }

            var bindings: [String: TypeReference] = [:]
            for (parameter, argument) in zip(signature.parameters, arguments) {
                guard argumentLabel(argument.label, matches: parameter) else {
                    return nil
                }
                if parameter.capturesSyntax {
                    continue
                }
                guard let expectedType = parameter.typeReference else {
                    continue
                }
                guard let actual = argument.type,
                    let actualType = materializedTypeReference(
                        for: actual,
                        resolver: literalBridgeResolver
                    )
                else {
                    return nil
                }
                guard
                    typeMatches(
                        actual: actualType,
                        expected: expectedType,
                        genericParameterNames: signature.genericParameterNames,
                        bindings: &bindings
                    )
                else {
                    return nil
                }
            }

            return Self.substitute(signature.returnType, using: bindings)
        }

        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private func argumentLabel(_ actualLabel: String?, matches parameter: MacroExpansionParameter)
        -> Bool
    {
        guard let actualLabel else {
            return true
        }
        let expectedLabel = parameter.externalLabel ?? parameter.localName
        return actualLabel == expectedLabel
    }

    private func materializedTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        case .nilLiteral:
            return .named("NilLiteral")
        default:
            return resolver.defaultDestinationType(for: type.displayName)
        }
    }

    private static func genericParameterName(_ parameter: GenericParameter) -> String {
        switch parameter {
        case .type(let name, _, _), .value(let name, _, _):
            return name
        }
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        genericParameterNames: Set<String>,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected, genericParameterNames.contains(name) {
            if let existing = bindings[name] {
                return existing == actual
            }
            bindings[name] = actual
            return true
        }

        if case .optional(let actualWrapped) = actual,
            case .generic(.named("Optional"), let expectedArguments) = expected,
            expectedArguments.count == 1
        {
            return typeMatches(
                actual: actualWrapped,
                expected: expectedArguments[0],
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        if case .generic(.named("Optional"), let actualArguments) = actual,
            actualArguments.count == 1,
            case .optional(let expectedWrapped) = expected
        {
            return typeMatches(
                actual: actualArguments[0],
                expected: expectedWrapped,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            else {
                return false
            }
            return zip(actualArguments, expectedArguments).allSatisfy {
                actualArgument, expectedArgument in
                typeMatches(
                    actual: actualArgument,
                    expected: expectedArgument,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }
            return zip(actualParameters, expectedParameters).allSatisfy {
                actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
                && typeMatches(
                    actual: actualReturn,
                    expected: expectedReturn,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        default:
            return false
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }
}

public struct DeclarationOperatorResolver: Sendable {
    public static let empty = DeclarationOperatorResolver(callablesByName: [:])

    private struct OperatorSignature: Sendable {
        var genericParameterNames: Set<String>
        var lhsType: TypeReference
        var rhsType: TypeReference
        var returnType: TypeReference
    }

    private let signaturesByName: [String: [OperatorSignature]]

    public init(callablesByName: [String: [CallableDeclaration]]) {
        self.signaturesByName = callablesByName.mapValues { callables in
            callables.compactMap { callable in
                guard callable.parameters.count == 2,
                    let lhsParameter = callable.parameters[0].typeReference,
                    let rhsParameter = callable.parameters[1].typeReference
                else {
                    return nil
                }
                let substitutions = callable.receiverType.map { ["Self": $0] } ?? [:]

                return OperatorSignature(
                    genericParameterNames: Set(
                        callable.genericParameters.map(Self.genericParameterName)),
                    lhsType: Self.substitute(lhsParameter, using: substitutions),
                    rhsType: Self.substitute(rhsParameter, using: substitutions),
                    returnType: Self.substitute(callable.returnType ?? .named("Void"), using: substitutions)
                )
            }
        }
    }

    public func binaryOperatorReturnType(
        symbol: String,
        lhs: BootstrapLiteralType,
        rhs: BootstrapLiteralType,
        literalBridgeResolver: LiteralBridgeResolver
    ) -> TypeReference? {
        guard let lhsType = materializedTypeReference(for: lhs, resolver: literalBridgeResolver),
            let rhsType = materializedTypeReference(for: rhs, resolver: literalBridgeResolver)
        else {
            return nil
        }

        let matches: [TypeReference] = signaturesByName[symbol, default: []].compactMap {
            signature in
            var bindings: [String: TypeReference] = [:]
            guard
                typeMatches(
                    actual: lhsType,
                    expected: signature.lhsType,
                    genericParameterNames: signature.genericParameterNames,
                    bindings: &bindings
                ),
                typeMatches(
                    actual: rhsType,
                    expected: signature.rhsType,
                    genericParameterNames: signature.genericParameterNames,
                    bindings: &bindings
                )
            else {
                return nil
            }
            return Self.substitute(signature.returnType, using: bindings)
        }

        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private func materializedTypeReference(
        for type: BootstrapLiteralType,
        resolver: LiteralBridgeResolver
    ) -> TypeReference? {
        switch type {
        case .typed(let typeReference):
            return typeReference
        case .nilLiteral:
            return .named("NilLiteral")
        default:
            return resolver.defaultDestinationType(for: type.displayName)
        }
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        genericParameterNames: Set<String>,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected, genericParameterNames.contains(name) {
            if let existing = bindings[name] {
                return existing == actual
            }
            bindings[name] = actual
            return true
        }

        if case .optional(let actualWrapped) = actual,
            case .generic(.named("Optional"), let expectedArguments) = expected,
            expectedArguments.count == 1
        {
            return typeMatches(
                actual: actualWrapped,
                expected: expectedArguments[0],
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        if case .generic(.named("Optional"), let actualArguments) = actual,
            actualArguments.count == 1,
            case .optional(let expectedWrapped) = expected
        {
            return typeMatches(
                actual: actualArguments[0],
                expected: expectedWrapped,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            else {
                return false
            }
            return zip(actualArguments, expectedArguments).allSatisfy {
                actualArgument, expectedArgument in
                typeMatches(
                    actual: actualArgument,
                    expected: expectedArgument,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }
            return zip(actualParameters, expectedParameters).allSatisfy {
                actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
                && typeMatches(
                    actual: actualReturn,
                    expected: expectedReturn,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        default:
            return false
        }
    }

    private static func genericParameterName(_ parameter: GenericParameter) -> String {
        switch parameter {
        case .type(let name, _, _), .value(let name, _, _):
            return name
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }
}

public struct DeclarationTypeCompatibilityResolver: Sendable {
    public static let empty = DeclarationTypeCompatibilityResolver(
        protocolsByName: [:],
        constructsByName: [:],
        enumsByName: [:],
        extensionsByTargetName: [:]
    )

    private struct TypeContext: Sendable {
        var name: String
        var arguments: [TypeReference]
    }

    private struct NominalConformance: Sendable {
        var declarationGenericParameterNames: [String]
        var extensionTargetType: TypeReference?
        var genericArgumentConstraints: [ExtensionGenericArgumentConstraint]
        var conformance: TypeReference
    }

    private let protocolNames: Set<String>
    private let conformancesByNominalName: [String: [NominalConformance]]

    public init(
        protocolsByName: [String: ProtocolDeclaration],
        constructsByName: [String: ConstructDeclaration],
        enumsByName: [String: EnumDeclaration],
        extensionsByTargetName: [String: [ExtensionDeclaration]]
    ) {
        self.protocolNames = Set(protocolsByName.keys)

        var conformances: [String: [NominalConformance]] = [:]
        for construct in constructsByName.values {
            let genericParameterNames = construct.genericParameters.map(Self.genericParameterName)
            conformances[construct.name, default: []].append(
                contentsOf: construct.conformances.map {
                    NominalConformance(
                        declarationGenericParameterNames: genericParameterNames,
                        extensionTargetType: nil,
                        genericArgumentConstraints: [],
                        conformance: $0
                    )
                }
            )
        }
        for enumeration in enumsByName.values {
            conformances[enumeration.name, default: []].append(
                contentsOf: enumeration.conformances.map {
                    NominalConformance(
                        declarationGenericParameterNames: [],
                        extensionTargetType: nil,
                        genericArgumentConstraints: [],
                        conformance: $0
                    )
                }
            )
        }
        for protocolDeclaration in protocolsByName.values {
            let genericParameterNames = protocolDeclaration.genericParameters.map(
                Self.genericParameterName
            )
            conformances[protocolDeclaration.name, default: []].append(
                contentsOf: protocolDeclaration.conformances.map {
                    NominalConformance(
                        declarationGenericParameterNames: genericParameterNames,
                        extensionTargetType: nil,
                        genericArgumentConstraints: [],
                        conformance: $0
                    )
                }
            )
        }
        for (targetName, extensions) in extensionsByTargetName {
            for extensionDeclaration in extensions {
                let genericParameterNames = genericParameterNames(for: targetName)
                conformances[targetName, default: []].append(
                    contentsOf: extensionDeclaration.conformances.map {
                        NominalConformance(
                            declarationGenericParameterNames: genericParameterNames,
                            extensionTargetType: extensionDeclaration.usesSpecializedTarget
                                ? extensionDeclaration.targetType : nil,
                            genericArgumentConstraints: extensionDeclaration
                                .genericArgumentConstraints,
                            conformance: $0
                        )
                    }
                )
            }
        }

        self.conformancesByNominalName = conformances

        func genericParameterNames(for targetName: String) -> [String] {
            if let construct = constructsByName[targetName] {
                return construct.genericParameters.map(Self.genericParameterName)
            }
            if let protocolDeclaration = protocolsByName[targetName] {
                return protocolDeclaration.genericParameters.map(Self.genericParameterName)
            }
            return []
        }
    }

    public func isAssignable(actual: TypeReference, expected: TypeReference) -> Bool {
        if actual == expected || Self.typesMatch(actual: actual, expected: expected) {
            return true
        }

        guard isKnownProtocol(expected) else {
            return false
        }

        return conforms(actual: actual, expectedProtocol: expected, visited: [])
    }

    private func conforms(
        actual: TypeReference,
        expectedProtocol: TypeReference,
        visited: Set<String>
    ) -> Bool {
        guard let actualContext = typeContext(for: actual) else {
            return false
        }
        let visitKey = "\(actual.displayName)->\(expectedProtocol.displayName)"
        guard !visited.contains(visitKey) else {
            return false
        }
        let nextVisited = visited.union([visitKey])

        for conformance in conformancesByNominalName[actualContext.name, default: []] {
            guard
                let substitution = conformanceSubstitution(
                    conformance,
                    actualContext: actualContext,
                    visited: nextVisited
                )
            else {
                continue
            }
            let resolvedConformance = Self.substitute(conformance.conformance, using: substitution)
            if Self.typesMatch(actual: resolvedConformance, expected: expectedProtocol) {
                return true
            }
            if conforms(
                actual: resolvedConformance,
                expectedProtocol: expectedProtocol,
                visited: nextVisited
            ) {
                return true
            }
        }

        return false
    }

    private func conformanceSubstitution(
        _ conformance: NominalConformance,
        actualContext: TypeContext,
        visited: Set<String>
    ) -> [String: TypeReference]? {
        if let extensionTargetType = conformance.extensionTargetType {
            return extensionSubstitution(
                targetType: extensionTargetType,
                genericArgumentConstraints: conformance.genericArgumentConstraints,
                actualContext: actualContext,
                visited: visited
            )
        }

        return Dictionary(
            uniqueKeysWithValues: zip(
                conformance.declarationGenericParameterNames,
                actualContext.arguments
            )
        )
    }

    private func extensionSubstitution(
        targetType: TypeReference,
        genericArgumentConstraints: [ExtensionGenericArgumentConstraint],
        actualContext: TypeContext,
        visited: Set<String>
    ) -> [String: TypeReference]? {
        guard let targetContext = typeContext(for: targetType),
            targetContext.name == actualContext.name,
            targetContext.arguments.count == actualContext.arguments.count
        else {
            return nil
        }

        var bindings: [String: TypeReference] = [:]
        let constraintNames = Set(genericArgumentConstraints.map(\.parameterName))

        for (pattern, actual) in zip(targetContext.arguments, actualContext.arguments) {
            if case .named(let name) = pattern,
                constraintNames.contains(name)
                    || !Self.typesMatch(actual: pattern, expected: actual)
            {
                if let existing = bindings[name],
                    !Self.typesMatch(actual: existing, expected: actual)
                {
                    return nil
                }
                bindings[name] = actual
                continue
            }

            guard Self.typesMatch(actual: actual, expected: pattern) else {
                return nil
            }
        }

        for genericConstraint in genericArgumentConstraints {
            guard let actual = bindings[genericConstraint.parameterName] else {
                return nil
            }
            let expected = Self.substitute(genericConstraint.constraint, using: bindings)
            guard isAssignable(actual: actual, expected: expected) else {
                return nil
            }
        }

        return bindings
    }

    private func isKnownProtocol(_ type: TypeReference) -> Bool {
        guard let context = typeContext(for: type) else {
            return false
        }
        return protocolNames.contains(context.name)
    }

    private func typeContext(for type: TypeReference) -> TypeContext? {
        switch type {
        case .named(let name):
            return TypeContext(name: name, arguments: [])
        case .member:
            return TypeContext(name: type.displayName, arguments: [])
        case .generic(let base, let arguments):
            guard let context = typeContext(for: base) else {
                return nil
            }
            return TypeContext(name: context.name, arguments: arguments)
        case .array(let element):
            return TypeContext(name: "Array", arguments: [element])
        case .optional(let wrapped):
            return TypeContext(name: "Optional", arguments: [wrapped])
        case .function, .variadic:
            return nil
        }
    }

    private static func typesMatch(actual: TypeReference, expected: TypeReference) -> Bool {
        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName && typesMatch(actual: actualBase, expected: expectedBase)
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typesMatch(actual: actualBase, expected: expectedBase)
            else {
                return false
            }
            return zip(actualArguments, expectedArguments).allSatisfy {
                typesMatch(actual: $0, expected: $1)
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typesMatch(actual: actualElement, expected: expectedElement)
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }
            return zip(actualParameters, expectedParameters).allSatisfy {
                typesMatch(actual: $0, expected: $1)
            } && typesMatch(actual: actualReturn, expected: expectedReturn)
        default:
            return false
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }

    private static func genericParameterName(_ parameter: GenericParameter) -> String {
        switch parameter {
        case .type(let name, _, _), .value(let name, _, _):
            return name
        }
    }
}

public struct DeclarationMemberResolver: Sendable {
    public static let empty = DeclarationMemberResolver(
        constructsByName: [:],
        enumsByName: [:],
        protocolsByName: [:],
        extensionsByTargetName: [:]
    )

    private struct ConstructMembers: Sendable {
        var genericParameterNames: [String]
        var genericDefaultArguments: [TypeReference?]
        var propertyTypes: [String: TypeReference]
        var initializerSignatures: [MemberInitializerSignature]
        var callableSignatures: [String: [MemberCallableSignature]]
    }

    private struct MemberInitializerSignature: Sendable {
        var parameters: [MemberCallableParameter]
        var returnType: TypeReference?
    }

    private struct MemberCallableSignature: Sendable {
        var genericParameterNames: [String]
        var parameters: [MemberCallableParameter]
        var returnType: TypeReference
    }

    private struct MemberCallableParameter: Sendable {
        var localName: String
        var externalLabel: String?
        var typeReference: TypeReference?
        var hasDefaultValue: Bool
    }

    private struct EnumCaseSignature: Sendable {
        var enumType: TypeReference
        var parameters: [MemberCallableParameter]
    }

    public struct MemberCallArgument: Sendable {
        public let label: String?
        public let typeReference: TypeReference?

        public init(label: String?, typeReference: TypeReference?) {
            self.label = label
            self.typeReference = typeReference
        }
    }

    private let membersByConstructName: [String: ConstructMembers]
    private let enumCaseSignaturesByQualifiedName: [String: EnumCaseSignature]
    private let enumCaseSignaturesByEnumName: [String: [String: EnumCaseSignature]]
    private let propertyTypesByProtocolName: [String: [String: TypeReference]]
    private let callableSignaturesByProtocolName: [String: [String: [MemberCallableSignature]]]
    private let genericParameterConstraintsByName: [String: TypeReference]

    public init(
        constructsByName: [String: ConstructDeclaration],
        enumsByName: [String: EnumDeclaration],
        protocolsByName: [String: ProtocolDeclaration],
        extensionsByTargetName: [String: [ExtensionDeclaration]]
    ) {
        self.genericParameterConstraintsByName = Self.genericParameterConstraints(
            constructsByName: constructsByName,
            protocolsByName: protocolsByName,
            extensionsByTargetName: extensionsByTargetName
        )
        self.propertyTypesByProtocolName = protocolsByName.mapValues { declaration in
            Self.protocolPropertyTypes(for: declaration)
        }
        self.callableSignaturesByProtocolName = protocolsByName.mapValues { declaration in
            Self.protocolCallableSignatures(for: declaration)
        }
        var enumCaseSignaturesByQualifiedName: [String: EnumCaseSignature] = [:]
        var enumCaseSignaturesByEnumName: [String: [String: EnumCaseSignature]] = [:]
        for (enumName, declaration) in enumsByName {
            let enumType: TypeReference =
                declaration.genericParameters.isEmpty
                ? .named(enumName)
                : .generic(
                    base: .named(enumName),
                    arguments: declaration.genericParameters.map { parameter in
                        switch parameter {
                        case .type(let name, _, _), .value(let name, _, _):
                            return .named(name)
                        }
                    }
                )
            for enumCase in declaration.cases {
                let signature = EnumCaseSignature(
                    enumType: enumType,
                    parameters: enumCase.associatedValues.map { associatedValue in
                        MemberCallableParameter(
                            localName: associatedValue.label ?? "_",
                            externalLabel: associatedValue.label,
                            typeReference: associatedValue.typeReference,
                            hasDefaultValue: false
                        )
                    }
                )
                enumCaseSignaturesByQualifiedName["\(enumName).\(enumCase.name)"] = signature
                enumCaseSignaturesByEnumName[enumName, default: [:]][enumCase.name] = signature
            }
        }
        self.enumCaseSignaturesByQualifiedName = enumCaseSignaturesByQualifiedName
        self.enumCaseSignaturesByEnumName = enumCaseSignaturesByEnumName
        self.membersByConstructName = constructsByName.mapValues { construct in
            let nestedTypeMap = Self.nestedTypeMap(for: construct)
            var propertyTypes: [String: TypeReference] = [:]
            for state in construct.states {
                propertyTypes[state.name] = Self.qualifyNestedLocalTypes(
                    state.type,
                    using: nestedTypeMap
                )
            }
            for binding in construct.bindings {
                propertyTypes[binding.name] = Self.qualifyNestedLocalTypes(
                    Self.simpleTypeReference(named: binding.typeName),
                    using: nestedTypeMap
                )
            }
            for derived in construct.deriveds {
                propertyTypes[derived.name] = Self.qualifyNestedLocalTypes(
                    Self.simpleTypeReference(named: derived.typeName),
                    using: nestedTypeMap
                )
            }
            for value in construct.values {
                propertyTypes[value.name] = Self.qualifyNestedLocalTypes(
                    Self.simpleTypeReference(named: value.typeName),
                    using: nestedTypeMap
                )
            }

            var callableSignatures: [String: [MemberCallableSignature]] = [:]
            var initializerSignatures = [
                MemberInitializerSignature(
                    parameters: Self.memberCallableParameters(
                        DeclarationGraph.directConstructApplicationParameters(for: construct),
                        using: nestedTypeMap
                    ),
                    returnType: nil
                )
            ]
            initializerSignatures.append(contentsOf: construct.initializers.map { initializer in
                MemberInitializerSignature(
                    parameters: Self.memberCallableParameters(
                        initializer.parameters,
                        using: nestedTypeMap
                    ),
                    returnType: initializer.returnType.map {
                        Self.qualifyNestedLocalTypes($0, using: nestedTypeMap)
                    }
                )
            })
            for extensionDeclaration in extensionsByTargetName[construct.name, default: []] {
                initializerSignatures.append(
                    contentsOf: extensionDeclaration.initializers.map { initializer in
                        MemberInitializerSignature(
                            parameters: Self.memberCallableParameters(
                                initializer.parameters,
                                using: nestedTypeMap
                            ),
                            returnType: initializer.returnType.map {
                                Self.qualifyNestedLocalTypes($0, using: nestedTypeMap)
                            }
                        )
                    }
                )
            }
            for callable in construct.callables {
                callableSignatures[callable.name, default: []].append(MemberCallableSignature(
                    genericParameterNames: callable.genericParameters.map(Self.genericParameterName),
                    parameters: Self.memberCallableParameters(
                        callable.parameters,
                        using: nestedTypeMap
                    ),
                    returnType: Self.qualifyNestedLocalTypes(
                        callable.returnType ?? .named("Void"),
                        using: nestedTypeMap
                    )
                ))
            }
            for extensionDeclaration in extensionsByTargetName[construct.name, default: []] {
                for callable in extensionDeclaration.callables {
                    callableSignatures[callable.name, default: []].append(MemberCallableSignature(
                        genericParameterNames: callable.genericParameters.map(Self.genericParameterName),
                        parameters: Self.memberCallableParameters(
                            callable.parameters,
                            using: nestedTypeMap
                        ),
                        returnType: Self.qualifyNestedLocalTypes(
                            callable.returnType ?? .named("Void"),
                            using: nestedTypeMap
                        )
                    ))
                }
            }

            return ConstructMembers(
                genericParameterNames: construct.genericParameters.map(Self.genericParameterName),
                genericDefaultArguments: construct.genericParameters.map {
                    switch $0 {
                    case .type(_, _, let defaultArgument):
                        return defaultArgument
                    case .value:
                        return nil
                    }
                },
                propertyTypes: propertyTypes,
                initializerSignatures: initializerSignatures,
                callableSignatures: callableSignatures
            )
        }
    }

    private static func nestedTypeMap(for construct: ConstructDeclaration) -> [String:
        TypeReference]
    {
        Dictionary(
            uniqueKeysWithValues: construct.constructs.map { nested in
                let localName =
                    nested.name.split(separator: ".").last.map(String.init) ?? nested.name
                return (localName, .member(base: .named(construct.name), name: localName))
            }
        )
    }

    private static func protocolCallableSignatures(
        for declaration: ProtocolDeclaration
    ) -> [String: [MemberCallableSignature]] {
        var signatures: [String: [MemberCallableSignature]] = [:]
        for callable in declaration.callables {
            signatures[callable.name, default: []].append(MemberCallableSignature(
                genericParameterNames: callable.genericParameters.map(Self.genericParameterName),
                parameters: Self.memberCallableParameters(callable.parameters, using: [:]),
                returnType: callable.returnType ?? .named("Void")
            ))
        }
        return signatures
    }

    private static func protocolPropertyTypes(
        for declaration: ProtocolDeclaration
    ) -> [String: TypeReference] {
        var propertyTypes: [String: TypeReference] = [:]
        for state in declaration.states {
            propertyTypes[state.name] = state.type
        }
        for binding in declaration.bindings {
            propertyTypes[binding.name] = simpleTypeReference(named: binding.typeName)
        }
        for derived in declaration.deriveds {
            propertyTypes[derived.name] = simpleTypeReference(named: derived.typeName)
        }
        for value in declaration.values {
            propertyTypes[value.name] = simpleTypeReference(named: value.typeName)
        }
        return propertyTypes
    }

    private static func memberCallableParameters(
        _ parameters: [GradientFunctionParameter],
        using nestedTypeMap: [String: TypeReference]
    ) -> [MemberCallableParameter] {
        parameters.map { parameter in
            MemberCallableParameter(
                localName: parameter.localName,
                externalLabel: parameter.externalLabel,
                typeReference: parameter.typeReference.map {
                    qualifyNestedLocalTypes($0, using: nestedTypeMap)
                },
                hasDefaultValue: parameter.defaultValue != nil
            )
        }
    }

    private static func genericParameterConstraints(
        constructsByName: [String: ConstructDeclaration],
        protocolsByName: [String: ProtocolDeclaration],
        extensionsByTargetName: [String: [ExtensionDeclaration]]
    ) -> [String: TypeReference] {
        var candidates: [String: [TypeReference]] = [:]

        func record(_ parameters: [GenericParameter]) {
            for parameter in parameters {
                guard case .type(let name, let constraint?, _) = parameter else {
                    continue
                }
                if candidates[name, default: []].contains(where: { $0.displayName == constraint.displayName }) {
                    continue
                }
                candidates[name, default: []].append(constraint)
            }
        }

        for construct in constructsByName.values {
            record(construct.genericParameters)
            for callable in construct.callables {
                record(callable.genericParameters)
            }
        }
        for declaration in protocolsByName.values {
            record(declaration.genericParameters)
            for callable in declaration.callables {
                record(callable.genericParameters)
            }
        }
        for extensions in extensionsByTargetName.values {
            for extensionDeclaration in extensions {
                for callable in extensionDeclaration.callables {
                    record(callable.genericParameters)
                }
            }
        }

        return Dictionary(
            uniqueKeysWithValues: candidates.compactMap { name, constraints in
                guard constraints.count == 1 else {
                    return nil
                }
                return (name, constraints[0])
            }
        )
    }

    private static func qualifyNestedLocalTypes(
        _ type: TypeReference,
        using nestedTypeMap: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return nestedTypeMap[name] ?? type
        case .member(let base, let name):
            return .member(base: qualifyNestedLocalTypes(base, using: nestedTypeMap), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: qualifyNestedLocalTypes(base, using: nestedTypeMap),
                arguments: arguments.map { qualifyNestedLocalTypes($0, using: nestedTypeMap) }
            )
        case .array(let element):
            return .array(qualifyNestedLocalTypes(element, using: nestedTypeMap))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { qualifyNestedLocalTypes($0, using: nestedTypeMap) },
                returnType: qualifyNestedLocalTypes(returnType, using: nestedTypeMap)
            )
        case .optional(let wrapped):
            return .optional(qualifyNestedLocalTypes(wrapped, using: nestedTypeMap))
        case .variadic(let element):
            return .variadic(qualifyNestedLocalTypes(element, using: nestedTypeMap))
        }
    }

    public func memberType(baseType: TypeReference, memberName: String) -> TypeReference? {
        if let protocolType = protocolPropertyType(baseType: baseType, memberName: memberName) {
            return protocolType
        }

        guard let context = constructContext(for: baseType),
            let members = membersByConstructName[context.name],
            let type = members.propertyTypes[memberName]
        else {
            return nil
        }
        return Self.substitute(
            type, using: genericSubstitution(for: members, arguments: context.arguments))
    }

    private func protocolPropertyType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        if case .named(let name) = baseType,
            let constrainedType = genericParameterConstraintsByName[name]
        {
            return protocolPropertyType(baseType: constrainedType, memberName: memberName)
        }

        guard let context = constructContext(for: baseType),
            let type = propertyTypesByProtocolName[context.name]?[memberName]
        else {
            return nil
        }
        return type
    }

    public func memberCallableReturnType(
        baseType: TypeReference,
        memberName: String,
        genericArguments: [TypeReference] = [],
        arguments: [MemberCallArgument] = []
    ) -> TypeReference? {
        if let protocolType = protocolCallableReturnType(
            baseType: baseType,
            memberName: memberName,
            genericArguments: genericArguments,
            arguments: arguments
        ) {
            return protocolType
        }

        guard let context = constructContext(for: baseType),
            let members = membersByConstructName[context.name],
            let signature = selectCallableSignature(
                members.callableSignatures[memberName, default: []],
                genericArguments: genericArguments,
                arguments: arguments,
                inheritedGenericParameterNames: Set(members.genericParameterNames),
                inheritedGenericBindings: genericSubstitution(
                    for: members,
                    arguments: context.arguments
                )
            )
        else {
            return nil
        }
        var substitution = genericSubstitution(for: members, arguments: context.arguments)
        substitution.merge(
            callableGenericSubstitution(
                for: signature,
                genericArguments: genericArguments,
                callArguments: arguments
            )
        ) { _, callable in callable }
        return Self.substitute(signature.returnType, using: substitution)
    }

    private func protocolCallableReturnType(
        baseType: TypeReference,
        memberName: String,
        genericArguments: [TypeReference],
        arguments: [MemberCallArgument]
    ) -> TypeReference? {
        if case .named(let name) = baseType,
            let constrainedType = genericParameterConstraintsByName[name]
        {
            return protocolCallableReturnType(
                baseType: constrainedType,
                memberName: memberName,
                genericArguments: genericArguments,
                arguments: arguments
            )
        }

        guard let context = constructContext(for: baseType),
            let signature = selectCallableSignature(
                callableSignaturesByProtocolName[context.name]?[memberName] ?? [],
                genericArguments: genericArguments,
                arguments: arguments
            )
        else {
            return nil
        }
        return Self.substitute(
            signature.returnType,
            using: callableGenericSubstitution(
                for: signature,
                genericArguments: genericArguments,
                callArguments: arguments
            )
        )
    }

    private func callableGenericSubstitution(
        for signature: MemberCallableSignature,
        genericArguments: [TypeReference],
        callArguments: [MemberCallArgument]
    ) -> [String: TypeReference] {
        var bindings: [String: TypeReference] = [:]
        if genericArguments.count == signature.genericParameterNames.count {
            bindings.merge(
                Dictionary(uniqueKeysWithValues: zip(signature.genericParameterNames, genericArguments))
            ) { _, explicit in explicit }
        }

        for (parameter, argument) in zip(signature.parameters, callArguments) {
            guard argumentLabel(argument.label, matches: parameter),
                let actualType = argument.typeReference,
                let expectedType = parameter.typeReference
            else {
                continue
            }
            _ = typeMatches(
                actual: actualType,
                expected: expectedType,
                genericParameterNames: Set(signature.genericParameterNames),
                bindings: &bindings
            )
        }

        return bindings
    }

    private func selectCallableSignature(
        _ signatures: [MemberCallableSignature],
        genericArguments: [TypeReference],
        arguments: [MemberCallArgument],
        inheritedGenericParameterNames: Set<String> = [],
        inheritedGenericBindings: [String: TypeReference] = [:]
    ) -> MemberCallableSignature? {
        signatures.first {
            callableSignature(
                $0,
                matchesGenericArguments: genericArguments,
                arguments: arguments,
                inheritedGenericParameterNames: inheritedGenericParameterNames,
                inheritedGenericBindings: inheritedGenericBindings
            )
        }
    }

    private func callableSignature(
        _ signature: MemberCallableSignature,
        matchesGenericArguments genericArguments: [TypeReference],
        arguments: [MemberCallArgument],
        inheritedGenericParameterNames: Set<String> = [],
        inheritedGenericBindings: [String: TypeReference] = [:]
    ) -> Bool {
        guard genericArguments.isEmpty || genericArguments.count == signature.genericParameterNames.count
        else {
            return false
        }
        guard arguments.count <= signature.parameters.count else {
            return false
        }

        var bindings = inheritedGenericBindings
        if genericArguments.count == signature.genericParameterNames.count {
            bindings.merge(
                Dictionary(uniqueKeysWithValues: zip(signature.genericParameterNames, genericArguments))
            ) { _, explicit in explicit }
        }

        let genericParameterNames = inheritedGenericParameterNames.union(signature.genericParameterNames)
        for (parameter, argument) in zip(signature.parameters, arguments) {
            guard argumentLabel(argument.label, matches: parameter) else {
                return false
            }
            guard let actualType = argument.typeReference,
                let expectedType = parameter.typeReference
            else {
                continue
            }
            guard
                typeMatches(
                    actual: actualType,
                    expected: expectedType,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            else {
                return false
            }
        }

        return true
    }

    private func argumentLabel(_ actualLabel: String?, matches parameter: MemberCallableParameter)
        -> Bool
    {
        guard let actualLabel else {
            return true
        }
        let expectedLabel = parameter.externalLabel ?? parameter.localName
        return actualLabel == expectedLabel
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        genericParameterNames: Set<String>,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected, genericParameterNames.contains(name) {
            if let existing = bindings[name] {
                return existing == actual
            }
            bindings[name] = actual
            return true
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            else {
                return false
            }
            return zip(actualArguments, expectedArguments).allSatisfy {
                typeMatches(
                    actual: $0,
                    expected: $1,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }
            return zip(actualParameters, expectedParameters).allSatisfy {
                typeMatches(
                    actual: $0,
                    expected: $1,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            }
                && typeMatches(
                    actual: actualReturn,
                    expected: expectedReturn,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
        default:
            return false
        }
    }

    public func constructType(forConstructorCallName name: String) -> TypeReference? {
        resolveConstructType(forConstructorCallName: name)
    }

    public func enumCaseReturnType(forCallName name: String) -> TypeReference? {
        enumCaseSignature(forCallName: name)?.enumType
    }

    public func enumCaseCallMatches(
        name: String,
        expected: TypeReference,
        arguments: [MemberCallArgument]
    ) -> Bool {
        guard let signature = enumCaseSignature(forCallName: name, expected: expected) else {
            return false
        }
        guard initializerArguments(arguments, match: signature.parameters) else {
            return false
        }
        return true
    }

    public func constructorCallReturnType(
        name: String,
        arguments: [MemberCallArgument]
    ) -> TypeReference? {
        guard let constructedType = resolveConstructType(forConstructorCallName: name),
            let context = constructContext(for: constructedType),
            let members = membersByConstructName[context.name]
        else {
            return nil
        }

        guard
            let signature = members.initializerSignatures.first(where: {
                initializerArguments(arguments, match: $0.parameters)
            })
        else {
            return constructedType
        }

        guard let returnType = signature.returnType else {
            return constructedType
        }

        var substitution = genericSubstitution(for: members, arguments: context.arguments)
        substitution["Self"] = constructedType
        let substitutedReturnType = Self.substitute(returnType, using: substitution)

        guard case .generic(let base, let resultArguments) = substitutedReturnType,
            case .named("Result") = base,
            resultArguments.count == 2
        else {
            return constructedType
        }

        return .generic(
            base: .named("Result"),
            arguments: [constructedType, resultArguments[1]]
        )
    }

    private func initializerArguments(
        _ arguments: [MemberCallArgument],
        match parameters: [MemberCallableParameter]
    ) -> Bool {
        var parameterIndex = 0
        for argument in arguments {
            var didMatch = false
            while parameterIndex < parameters.count {
                let parameter = parameters[parameterIndex]
                if argumentLabel(argument.label, matches: parameter) {
                    parameterIndex += 1
                    didMatch = true
                    break
                }
                guard parameter.hasDefaultValue else {
                    return false
                }
                parameterIndex += 1
            }
            guard didMatch else {
                return false
            }
        }

        while parameterIndex < parameters.count {
            guard parameters[parameterIndex].hasDefaultValue else {
                return false
            }
            parameterIndex += 1
        }
        return true
    }

    private func enumCaseSignature(
        forCallName name: String,
        expected: TypeReference? = nil
    ) -> EnumCaseSignature? {
        if name.hasPrefix(".") {
            guard let expectedEnumName = expected.flatMap(enumName) else {
                return nil
            }
            let caseName = String(name.dropFirst())
            return enumCaseSignaturesByEnumName[expectedEnumName]?[caseName]
        }

        guard let dot = name.lastIndex(of: ".") else {
            return nil
        }
        let enumName = String(name[..<dot])
        let caseName = String(name[name.index(after: dot)...])
        return enumCaseSignaturesByQualifiedName["\(enumName).\(caseName)"]
    }

    private func enumName(of type: TypeReference) -> String? {
        switch type {
        case .named(let name):
            return name
        case .member:
            return type.displayName
        case .generic(let base, _):
            return enumName(of: base)
        case .optional(let wrapped):
            return enumName(of: wrapped)
        case .array, .function, .variadic:
            return nil
        }
    }

    private func resolveConstructType(forConstructorCallName name: String) -> TypeReference? {
        guard let constructType = Self.parseConstructTypeReference(from: name),
            let context = constructContext(for: constructType),
            let members = membersByConstructName[context.name]
        else {
            return nil
        }

        guard
            members.genericParameterNames.isEmpty
                || resolvedGenericArguments(
                    for: members,
                    providedArguments: context.arguments
                ) != nil
        else {
            return nil
        }

        guard let resolvedArguments = resolvedGenericArguments(
            for: members,
            providedArguments: context.arguments
        ) else {
            return constructType
        }

        guard !resolvedArguments.isEmpty else {
            return constructType
        }

        return .generic(base: .named(context.name), arguments: resolvedArguments)
    }

    private func genericSubstitution(
        for members: ConstructMembers,
        arguments: [TypeReference]
    ) -> [String: TypeReference] {
        guard let resolvedArguments = resolvedGenericArguments(
            for: members,
            providedArguments: arguments
        ) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: zip(members.genericParameterNames, resolvedArguments))
    }

    private func resolvedGenericArguments(
        for members: ConstructMembers,
        providedArguments: [TypeReference]
    ) -> [TypeReference]? {
        guard providedArguments.count <= members.genericParameterNames.count else {
            return nil
        }

        var resolvedArguments = providedArguments
        if providedArguments.count == members.genericParameterNames.count {
            return resolvedArguments
        }

        for defaultArgument in members.genericDefaultArguments.dropFirst(providedArguments.count) {
            guard let defaultArgument else {
                return nil
            }
            resolvedArguments.append(defaultArgument)
        }

        return resolvedArguments
    }

    private func constructContext(for type: TypeReference) -> (
        name: String, arguments: [TypeReference]
    )? {
        switch type {
        case .named(let name):
            return (name, [])
        case .member:
            return (type.displayName, [])
        case .generic(let base, let arguments):
            guard let context = constructContext(for: base) else {
                return nil
            }
            return (context.name, arguments)
        case .array(let element):
            return ("Array", [element])
        case .optional(let wrapped):
            return ("Optional", [wrapped])
        case .function, .variadic:
            return nil
        }
    }

    private static func simpleTypeReference(named name: String) -> TypeReference {
        if let parsed = parseConstructTypeReference(from: name) {
            return parsed
        }

        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") {
            trimmed.removeLast()
            return .optional(simpleTypeReference(named: trimmed))
        }
        return .named(trimmed)
    }

    private static func parseConstructTypeReference(from raw: String) -> TypeReference? {
        do {
            var parser = try Parser(source: raw)
            let type = try parser.parseTypeReferenceNode()
            try parser.consume(.eof)
            return type
        } catch {
            return nil
        }
    }

    private static func genericParameterName(_ parameter: GenericParameter) -> String {
        switch parameter {
        case .type(let name, _, _), .value(let name, _, _):
            return name
        }
    }

    private static func substitute(
        _ type: TypeReference,
        using substitutions: [String: TypeReference]
    ) -> TypeReference {
        switch type {
        case .named(let name):
            return substitutions[name] ?? type
        case .member(let base, let name):
            return .member(base: substitute(base, using: substitutions), name: name)
        case .generic(let base, let arguments):
            return .generic(
                base: substitute(base, using: substitutions),
                arguments: arguments.map { substitute($0, using: substitutions) }
            )
        case .array(let element):
            return .array(substitute(element, using: substitutions))
        case .function(let parameters, let returnType):
            return .function(
                parameters: parameters.map { substitute($0, using: substitutions) },
                returnType: substitute(returnType, using: substitutions)
            )
        case .optional(let wrapped):
            return .optional(substitute(wrapped, using: substitutions))
        case .variadic(let element):
            return .variadic(substitute(element, using: substitutions))
        }
    }
}
