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
    public let realizedLiteralBridges: [RealizedLiteralBridge]

    public init(files: [ParsedSourceFile]) {
        let protocols = Self.collectProtocols(from: files)
        let constructs = Self.collectConstructs(from: files, protocols: protocols)

        self.protocolsByName = protocols
        self.constructsByName = constructs
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
    public static let empty = DeclarationMemberResolver(memberTypesByConstructName: [:])

    private let memberTypesByConstructName: [String: [String: TypeReference]]

    public init(constructsByName: [String: ConstructDeclaration]) {
        self.memberTypesByConstructName = constructsByName.mapValues { construct in
            var members: [String: TypeReference] = [:]
            for state in construct.states {
                members[state.name] = state.type
            }
            for environment in construct.environments {
                members[environment.name] = environment.type
            }
            for binding in construct.bindings {
                members[binding.name] = Self.simpleTypeReference(named: binding.typeName)
            }
            for derived in construct.deriveds {
                members[derived.name] = Self.simpleTypeReference(named: derived.typeName)
            }
            for value in construct.values {
                members[value.name] = Self.simpleTypeReference(named: value.typeName)
            }
            return members
        }
    }

    private init(memberTypesByConstructName: [String: [String: TypeReference]]) {
        self.memberTypesByConstructName = memberTypesByConstructName
    }

    public func memberType(baseType: TypeReference, memberName: String) -> TypeReference? {
        guard let constructName = constructName(for: baseType) else {
            return nil
        }
        return memberTypesByConstructName[constructName]?[memberName]
    }

    private func constructName(for type: TypeReference) -> String? {
        switch type {
        case .named(let name):
            return name
        case .member(_, let name):
            return name
        case .generic(let base, _):
            return constructName(for: base)
        case .array:
            return "Array"
        case .optional:
            return "Optional"
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
}
