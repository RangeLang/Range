import Foundation

public struct RealizedLiteralBridge: Hashable {
    public let constructName: String
    public let carrierTypeName: String
    public let parameterLabel: String?

    public init(
        constructName: String,
        carrierTypeName: String,
        parameterLabel: String?
    ) {
        self.constructName = constructName
        self.carrierTypeName = carrierTypeName
        self.parameterLabel = parameterLabel
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
                    parameterLabel: initializer.parameters[0].externalLabel
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
