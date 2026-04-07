import Foundation

public struct RealizedLiteralBridge: Hashable, Sendable {
    public let constructName: String
    public let carrierTypeName: String
    public let parameterLabel: String?
    public let isCore: Bool

    public init(
        constructName: String,
        carrierTypeName: String,
        parameterLabel: String?,
        isCore: Bool
    ) {
        self.constructName = constructName
        self.carrierTypeName = carrierTypeName
        self.parameterLabel = parameterLabel
        self.isCore = isCore
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
                let realizedInitializers = carriedProtocolInitializerMacros(
                    for: declaration.initializers,
                    conformances: declaration.conformances,
                    protocols: protocols
                )

                registry[declaration.name] = ConstructDeclaration(
                    macros: declaration.macros,
                    kind: declaration.kind,
                    attribute: declaration.attribute,
                    name: declaration.name,
                    genericParameters: declaration.genericParameters,
                    conformances: declaration.conformances,
                    states: declaration.states,
                    environments: declaration.environments,
                    bindings: declaration.bindings,
                    deriveds: declaration.deriveds,
                    values: declaration.values,
                    initializers: realizedInitializers,
                    callables: declaration.callables
                )
            }
        }
        return registry
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
                    constructName: construct.name,
                    carrierTypeName: literalMacro.genericArguments[0].displayName,
                    parameterLabel: initializer.parameters[0].externalLabel,
                    isCore: construct.isCore
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
            var propertyTypes: [String: TypeReference] = [:]
            for state in construct.states {
                propertyTypes[state.name] = state.type
            }
            for environment in construct.environments {
                propertyTypes[environment.name] = environment.type
            }
            for binding in construct.bindings {
                propertyTypes[binding.name] = Self.simpleTypeReference(named: binding.typeName)
            }
            for derived in construct.deriveds {
                propertyTypes[derived.name] = Self.simpleTypeReference(named: derived.typeName)
            }
            for value in construct.values {
                propertyTypes[value.name] = Self.simpleTypeReference(named: value.typeName)
            }

            var callableReturnTypes: [String: TypeReference] = [:]
            for callable in construct.callables {
                callableReturnTypes[callable.name] = callable.returnType ?? .named("Void")
            }

            return ConstructMembers(
                genericParameterNames: construct.genericParameters.map(Self.genericParameterName),
                propertyTypes: propertyTypes,
                callableReturnTypes: callableReturnTypes
            )
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
        case .member(_, let name):
            return (name, [])
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
