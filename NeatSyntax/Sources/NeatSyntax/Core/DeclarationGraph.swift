import Foundation

public struct RealizedInitTarget: Hashable, Sendable {
    public let constructName: String
    public let parameterLabels: [String?]
    public let isCore: Bool

    public init(
        constructName: String,
        parameterLabels: [String?],
        isCore: Bool
    ) {
        self.constructName = constructName
        self.parameterLabels = parameterLabels
        self.isCore = isCore
    }
}

public struct RealizedLiteralBridge: Hashable, Sendable {
    public let initTarget: RealizedInitTarget
    public let carrierTypeName: String

    public init(
        initTarget: RealizedInitTarget,
        carrierTypeName: String,
    ) {
        self.initTarget = initTarget
        self.carrierTypeName = carrierTypeName
    }

    public var constructName: String {
        initTarget.constructName
    }

    public var parameterLabel: String? {
        guard initTarget.parameterLabels.count == 1 else {
            return nil
        }
        return initTarget.parameterLabels[0]
    }

    public var isCore: Bool {
        initTarget.isCore
    }
}

public struct DeclarationGraph {
    public let protocolsByName: [String: ProtocolDeclaration]
    public let constructsByName: [String: ConstructDeclaration]
    public let callablesByName: [String: [CallableDeclaration]]
    public let realizedLiteralBridges: [RealizedLiteralBridge]

    public init(files: [ParsedSourceFile]) {
        let protocols = Self.collectProtocols(from: files)
        let constructs = Self.collectConstructs(from: files, protocols: protocols)
        let callables = Self.collectCallables(from: files)

        self.protocolsByName = protocols
        self.constructsByName = constructs
        self.callablesByName = callables
        self.realizedLiteralBridges = Self.collectRealizedLiteralBridges(from: constructs)
    }

    public var literalBridgeResolver: LiteralBridgeResolver {
        LiteralBridgeResolver(realizedLiteralBridges: realizedLiteralBridges)
    }

    public var memberResolver: DeclarationMemberResolver {
        DeclarationMemberResolver(constructsByName: constructsByName)
    }

    public var operatorResolver: DeclarationOperatorResolver {
        DeclarationOperatorResolver(callablesByName: callablesByName)
    }

    public var syntaxResolver: DeclarationSyntaxResolver {
        DeclarationSyntaxResolver(
            protocolsByName: protocolsByName,
            constructsByName: constructsByName
        )
    }

    static func collectProtocols(from files: [ParsedSourceFile]) -> [String: ProtocolDeclaration] {
        var registry: [String: ProtocolDeclaration] = [:]
        for parsedFile in files {
            for declaration in protocols(in: parsedFile.sourceFile) {
                registry[declaration.name] = declaration
            }
        }
        return registry
    }

    static func collectConstructs(
        from files: [ParsedSourceFile],
        protocols: [String: ProtocolDeclaration]
    ) -> [String: ConstructDeclaration] {
        var registry: [String: ConstructDeclaration] = [:]
        for parsedFile in files {
            for declaration in constructs(in: parsedFile.sourceFile) {
                collectConstruct(
                    declaration,
                    qualifiedName: declaration.name,
                    into: &registry,
                    protocols: protocols
                )
            }
        }
        return registry
    }

    private static func collectConstruct(
        _ declaration: ConstructDeclaration,
        qualifiedName: String,
        into registry: inout [String: ConstructDeclaration],
        protocols: [String: ProtocolDeclaration]
    ) {
        let realizedInitializers = carriedProtocolInitializerMacros(
            for: declaration.initializers,
            conformances: declaration.conformances,
            protocols: protocols
        )

        let qualifiedChildren = declaration.constructs.map { child in
            qualifiedConstruct(child, qualifiedName: "\(qualifiedName).\(child.name)")
        }

        registry[qualifiedName] = ConstructDeclaration(
            macros: declaration.macros,
            kind: declaration.kind,
            attribute: declaration.attribute,
            name: qualifiedName,
            genericParameters: declaration.genericParameters,
            conformances: declaration.conformances,
            states: declaration.states,
            environments: declaration.environments,
            bindings: declaration.bindings,
            deriveds: declaration.deriveds,
            values: declaration.values,
            initializers: realizedInitializers,
            callables: declaration.callables,
            constructs: qualifiedChildren
        )

        for child in declaration.constructs {
            collectConstruct(
                child,
                qualifiedName: "\(qualifiedName).\(child.name)",
                into: &registry,
                protocols: protocols
            )
        }
    }

    private static func qualifiedConstruct(
        _ declaration: ConstructDeclaration,
        qualifiedName: String
    ) -> ConstructDeclaration {
        ConstructDeclaration(
            macros: declaration.macros,
            kind: declaration.kind,
            attribute: declaration.attribute,
            name: qualifiedName,
            genericParameters: declaration.genericParameters,
            conformances: declaration.conformances,
            states: declaration.states,
            environments: declaration.environments,
            bindings: declaration.bindings,
            deriveds: declaration.deriveds,
            values: declaration.values,
            initializers: declaration.initializers,
            callables: declaration.callables,
            constructs: declaration.constructs.map {
                qualifiedConstruct($0, qualifiedName: "\(qualifiedName).\($0.name)")
            }
        )
    }

    static func collectCallables(from files: [ParsedSourceFile]) -> [String: [CallableDeclaration]] {
        var registry: [String: [CallableDeclaration]] = [:]
        for parsedFile in files {
            for declaration in callables(in: parsedFile.sourceFile) {
                registry[declaration.name, default: []].append(declaration)
            }
        }
        return registry
    }

    static func collectRealizedLiteralBridges(
        from constructs: [String: ConstructDeclaration]
    ) -> [RealizedLiteralBridge] {
        constructs.values.flatMap { construct in
            construct.initializers.compactMap { initializer in
                guard initializer.parameters.count == 1 else {
                    return nil
                }

                guard
                    let literalMacro = initializer.macros.first(where: { $0.name == "literal" }),
                    literalMacro.genericArguments.count == 1
                else {
                    return nil
                }

                return RealizedLiteralBridge(
                    initTarget: RealizedInitTarget(
                        constructName: construct.name,
                        parameterLabels: initializer.parameters.map(\.externalLabel),
                        isCore: construct.isCore
                    ),
                    carrierTypeName: literalMacro.genericArguments[0].displayName
                )
            }
        }
    }

    static func protocols(in sourceFile: SourceFileNode) -> [ProtocolDeclaration] {
        switch sourceFile {
        case .protocolDefinition(let declaration):
            return [declaration]
        case .module(let module):
            return module.protocols
        case .construct, .enumeration, .mainBlock, .macro, .extensions:
            return []
        }
    }

    static func constructs(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    static func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables
        case .construct, .enumeration, .mainBlock, .macro, .protocolDefinition, .extensions:
            return []
        }
    }

    static func carriedProtocolInitializerMacros(
        for initializers: [InitializerDeclaration],
        conformances: [TypeReference],
        protocols: [String: ProtocolDeclaration]
    ) -> [InitializerDeclaration] {
        let requirementInitializers = conformances.compactMap { protocols[$0.displayName] }
            .flatMap(\.initializers)

        guard !requirementInitializers.isEmpty else {
            return initializers
        }

        return initializers.map { initializer in
            let carried =
                requirementInitializers
                .filter { requirement in
                    carriedInitializerSignatureMatches(lhs: requirement, rhs: initializer)
                }
                .flatMap(\.macros)

            guard !carried.isEmpty else {
                return initializer
            }

            let mergedMacros =
                initializer.macros
                + carried.filter { carriedMacro in
                    !initializer.macros.contains {
                        $0.name == carriedMacro.name
                            && $0.genericArguments == carriedMacro.genericArguments
                            && $0.argumentClause == carriedMacro.argumentClause
                    }
                }

            return InitializerDeclaration(
                macros: mergedMacros,
                parameters: initializer.parameters,
                body: initializer.body
            )
        }
    }

    static func carriedInitializerSignatureMatches(
        lhs: InitializerDeclaration,
        rhs: InitializerDeclaration
    ) -> Bool {
        lhs.parameters.elementsEqual(
            rhs.parameters,
            by: {
                $0.localName == $1.localName
                    && $0.externalLabel == $1.externalLabel
                    && $0.typeReference == $1.typeReference
                    && $0.slotName == $1.slotName
            })
    }
}

public struct DeclarationSyntaxResolver {
    private let protocolsByName: [String: ProtocolDeclaration]
    private let constructsByName: [String: ConstructDeclaration]

    public init(
        protocolsByName: [String: ProtocolDeclaration],
        constructsByName: [String: ConstructDeclaration]
    ) {
        self.protocolsByName = protocolsByName
        self.constructsByName = constructsByName
    }

    public func typeConformsToSyntax(_ typeReference: TypeReference?) -> Bool {
        guard let typeName = nominalName(of: typeReference) else {
            return false
        }
        return declaration(named: typeName, conformsTo: "Syntax", visited: [])
    }

    private func declaration(
        named name: String,
        conformsTo targetProtocol: String,
        visited: Set<String>
    ) -> Bool {
        if name == targetProtocol {
            return true
        }
        if visited.contains(name) {
            return false
        }
        var nextVisited = visited
        nextVisited.insert(name)

        if let protocolDeclaration = protocolsByName[name] {
            return protocolDeclaration.conformances.contains {
                conformance in
                guard let conformanceName = nominalName(of: conformance) else {
                    return false
                }
                return declaration(
                    named: conformanceName,
                    conformsTo: targetProtocol,
                    visited: nextVisited
                )
            }
        }

        if let constructDeclaration = constructsByName[name] {
            return constructDeclaration.conformances.contains {
                conformance in
                guard let conformanceName = nominalName(of: conformance) else {
                    return false
                }
                return declaration(
                    named: conformanceName,
                    conformsTo: targetProtocol,
                    visited: nextVisited
                )
            }
        }

        return false
    }

    private func nominalName(of typeReference: TypeReference?) -> String? {
        guard let typeReference else {
            return nil
        }
        switch typeReference {
        case .named(let name):
            return name
        case .generic(let base, _):
            return nominalName(of: base)
        case .member:
            return typeReference.displayName
        case .array, .function, .optional, .variadic:
            return nil
        }
    }
}

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
                    genericParameterNames: Set(macro.genericParameters),
                    parameters: macro.parameters.map {
                        MacroExpansionParameter(
                            localName: $0.localName,
                            externalLabel: $0.externalLabel,
                            typeReference: $0.typeReference,
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
                guard typeMatches(
                    actual: actualType,
                    expected: expectedType,
                    genericParameterNames: signature.genericParameterNames,
                    bindings: &bindings
                ) else {
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
            return actualName == expectedName && typeMatches(
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
            return zip(actualArguments, expectedArguments).allSatisfy { actualArgument, expectedArgument in
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
            return zip(actualParameters, expectedParameters).allSatisfy { actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            } && typeMatches(
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

                return OperatorSignature(
                    genericParameterNames: Set(callable.genericParameters.map(Self.genericParameterName)),
                    lhsType: lhsParameter,
                    rhsType: rhsParameter,
                    returnType: callable.returnType ?? .named("Void")
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

        let matches: [TypeReference] = signaturesByName[symbol, default: []].compactMap { signature in
            var bindings: [String: TypeReference] = [:]
            guard typeMatches(
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
            return actualName == expectedName && typeMatches(
                actual: actualBase,
                expected: expectedBase,
                genericParameterNames: genericParameterNames,
                bindings: &bindings
            )
        case (.generic(let actualBase, let actualArguments), .generic(let expectedBase, let expectedArguments)):
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
            return zip(actualArguments, expectedArguments).allSatisfy { actualArgument, expectedArgument in
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
            return zip(actualParameters, expectedParameters).allSatisfy { actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    genericParameterNames: genericParameterNames,
                    bindings: &bindings
                )
            } && typeMatches(
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

public struct DeclarationMemberResolver: Sendable {
    public static let empty = DeclarationMemberResolver(constructsByName: [:])

    private struct ConstructMembers: Sendable {
        var genericParameterNames: [String]
        var propertyTypes: [String: TypeReference]
        var callableReturnTypes: [String: TypeReference]
    }

    private let membersByConstructName: [String: ConstructMembers]

    public init(constructsByName: [String: ConstructDeclaration]) {
        self.membersByConstructName = constructsByName.mapValues { construct in
            let nestedTypeMap = Self.nestedTypeMap(for: construct)
            var propertyTypes: [String: TypeReference] = [:]
            for state in construct.states {
                propertyTypes[state.name] = Self.qualifyNestedLocalTypes(
                    state.type,
                    using: nestedTypeMap
                )
            }
            for environment in construct.environments {
                propertyTypes[environment.name] = Self.qualifyNestedLocalTypes(
                    environment.type,
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

            var callableReturnTypes: [String: TypeReference] = [:]
            for callable in construct.callables {
                callableReturnTypes[callable.name] = Self.qualifyNestedLocalTypes(
                    callable.returnType ?? .named("Void"),
                    using: nestedTypeMap
                )
            }

            return ConstructMembers(
                genericParameterNames: construct.genericParameters.map(Self.genericParameterName),
                propertyTypes: propertyTypes,
                callableReturnTypes: callableReturnTypes
            )
        }
    }

    private static func nestedTypeMap(for construct: ConstructDeclaration) -> [String: TypeReference] {
        Dictionary(
            uniqueKeysWithValues: construct.constructs.map { nested in
                let localName = nested.name.split(separator: ".").last.map(String.init) ?? nested.name
                return (localName, .member(base: .named(construct.name), name: localName))
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
        guard let context = constructContext(for: baseType),
            let members = membersByConstructName[context.name],
            let type = members.propertyTypes[memberName]
        else {
            return nil
        }
        return Self.substitute(type, using: genericSubstitution(for: members, arguments: context.arguments))
    }

    public func memberCallableReturnType(
        baseType: TypeReference,
        memberName: String
    ) -> TypeReference? {
        guard let context = constructContext(for: baseType),
            let members = membersByConstructName[context.name],
            let type = members.callableReturnTypes[memberName]
        else {
            return nil
        }
        return Self.substitute(type, using: genericSubstitution(for: members, arguments: context.arguments))
    }

    private func genericSubstitution(
        for members: ConstructMembers,
        arguments: [TypeReference]
    ) -> [String: TypeReference] {
        Dictionary(uniqueKeysWithValues: zip(members.genericParameterNames, arguments))
    }

    private func constructContext(for type: TypeReference) -> (name: String, arguments: [TypeReference])? {
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
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") {
            trimmed.removeLast()
            return .optional(simpleTypeReference(named: trimmed))
        }
        return .named(trimmed)
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
