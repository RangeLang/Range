import Foundation

public struct DeclarationGraphViews {
    public let literalBridgeResolver: LiteralBridgeResolver
    public let memberResolver: DeclarationMemberResolver
    public let operatorResolver: DeclarationOperatorResolver
    public let typeCompatibilityResolver: DeclarationTypeCompatibilityResolver
    public let registryView: DeclarationRegistryView
    public let syntaxResolver: DeclarationSyntaxResolver

    public init(
        literalBridgeResolver: LiteralBridgeResolver,
        memberResolver: DeclarationMemberResolver,
        operatorResolver: DeclarationOperatorResolver,
        typeCompatibilityResolver: DeclarationTypeCompatibilityResolver,
        registryView: DeclarationRegistryView,
        syntaxResolver: DeclarationSyntaxResolver
    ) {
        self.literalBridgeResolver = literalBridgeResolver
        self.memberResolver = memberResolver
        self.operatorResolver = operatorResolver
        self.typeCompatibilityResolver = typeCompatibilityResolver
        self.registryView = registryView
        self.syntaxResolver = syntaxResolver
    }
}

public struct DeclarationRegistryView {
    private let protocolsByName: [String: ProtocolDeclaration]
    private let constructsByName: [String: ConstructDeclaration]
    private let enumsByName: [String: EnumDeclaration]
    private let macrosByName: [String: MacroDeclaration]
    private let extensionsByTargetName: [String: [ExtensionDeclaration]]
    private let topLevelStatesByFilePath: [String: [StateDeclaration]]
    private let statesByConstructName: [String: [StateDeclaration]]
    private let bindingsByConstructName: [String: [BindingDeclaration]]
    private let derivedsByConstructName: [String: [DerivedDeclaration]]
    private let valuesByConstructName: [String: [ValueDeclaration]]
    private let initializersByConstructName: [String: [InitializerDeclaration]]
    private let parametersByCallableIdentity: [String: [RangeFunctionParameter]]
    private let parametersByInitializerIdentity: [String: [RangeFunctionParameter]]
    private let callablesByName: [String: [CallableDeclaration]]

    public init(
        protocolsByName: [String: ProtocolDeclaration],
        constructsByName: [String: ConstructDeclaration],
        enumsByName: [String: EnumDeclaration],
        macrosByName: [String: MacroDeclaration],
        extensionsByTargetName: [String: [ExtensionDeclaration]],
        topLevelStatesByFilePath: [String: [StateDeclaration]],
        statesByConstructName: [String: [StateDeclaration]],
        bindingsByConstructName: [String: [BindingDeclaration]],
        derivedsByConstructName: [String: [DerivedDeclaration]],
        valuesByConstructName: [String: [ValueDeclaration]],
        initializersByConstructName: [String: [InitializerDeclaration]],
        parametersByCallableIdentity: [String: [RangeFunctionParameter]],
        parametersByInitializerIdentity: [String: [RangeFunctionParameter]],
        callablesByName: [String: [CallableDeclaration]]
    ) {
        self.protocolsByName = protocolsByName
        self.constructsByName = constructsByName
        self.enumsByName = enumsByName
        self.macrosByName = macrosByName
        self.extensionsByTargetName = extensionsByTargetName
        self.topLevelStatesByFilePath = topLevelStatesByFilePath
        self.statesByConstructName = statesByConstructName
        self.bindingsByConstructName = bindingsByConstructName
        self.derivedsByConstructName = derivedsByConstructName
        self.valuesByConstructName = valuesByConstructName
        self.initializersByConstructName = initializersByConstructName
        self.parametersByCallableIdentity = parametersByCallableIdentity
        self.parametersByInitializerIdentity = parametersByInitializerIdentity
        self.callablesByName = callablesByName
    }

    public var allConstructsByName: [String: ConstructDeclaration] {
        constructsByName
    }

    public func `protocol`(named name: String) -> ProtocolDeclaration? {
        protocolsByName[name]
    }

    public func construct(named name: String) -> ConstructDeclaration? {
        constructsByName[name]
    }

    public func enumeration(named name: String) -> EnumDeclaration? {
        enumsByName[name]
    }

    public func macro(named name: String) -> MacroDeclaration? {
        macrosByName[name]
    }

    public func extensions(targeting targetName: String) -> [ExtensionDeclaration] {
        extensionsByTargetName[targetName, default: []]
    }

    public func topLevelStates(inFilePath path: String) -> [StateDeclaration] {
        topLevelStatesByFilePath[path, default: []]
    }

    public func states(onConstruct named: String) -> [StateDeclaration] {
        statesByConstructName[named, default: []]
    }

    public func bindings(onConstruct named: String) -> [BindingDeclaration] {
        bindingsByConstructName[named, default: []]
    }

    public func deriveds(onConstruct named: String) -> [DerivedDeclaration] {
        derivedsByConstructName[named, default: []]
    }

    public func values(onConstruct named: String) -> [ValueDeclaration] {
        valuesByConstructName[named, default: []]
    }

    public func initializers(onConstruct named: String) -> [InitializerDeclaration] {
        initializersByConstructName[named, default: []]
    }

    public func callables(named name: String) -> [CallableDeclaration] {
        callablesByName[name, default: []]
    }

    public func callableIdentity(
        ownerName: String?,
        declaration: CallableDeclaration
    ) -> String {
        DeclarationGraph.callableIdentity(ownerName: ownerName, declaration: declaration)
    }

    public func initializerIdentity(
        constructName: String,
        declaration: InitializerDeclaration
    ) -> String {
        DeclarationGraph.initializerIdentity(
            constructName: constructName,
            declaration: declaration
        )
    }

    public func parameters(
        ofCallable declaration: CallableDeclaration,
        ownerName: String?
    ) -> [RangeFunctionParameter] {
        parametersByCallableIdentity[
            callableIdentity(ownerName: ownerName, declaration: declaration),
            default: []
        ]
    }

    public func parameters(
        ofInitializer declaration: InitializerDeclaration,
        constructName: String
    ) -> [RangeFunctionParameter] {
        parametersByInitializerIdentity[
            initializerIdentity(constructName: constructName, declaration: declaration),
            default: []
        ]
    }

    public func hasProtocol(named name: String) -> Bool {
        protocolsByName[name] != nil
    }

    public func hasConstruct(named name: String) -> Bool {
        constructsByName[name] != nil
    }

    public func hasEnumeration(named name: String) -> Bool {
        enumsByName[name] != nil
    }

    public func hasMacro(named name: String) -> Bool {
        macrosByName[name] != nil
    }

    public func hasExtensions(targeting targetName: String) -> Bool {
        !(extensionsByTargetName[targetName] ?? []).isEmpty
    }

    public func hasTopLevelStates(inFilePath path: String) -> Bool {
        !(topLevelStatesByFilePath[path] ?? []).isEmpty
    }

    public func hasStates(onConstruct named: String) -> Bool {
        !(statesByConstructName[named] ?? []).isEmpty
    }

    public func hasBindings(onConstruct named: String) -> Bool {
        !(bindingsByConstructName[named] ?? []).isEmpty
    }

    public func hasDeriveds(onConstruct named: String) -> Bool {
        !(derivedsByConstructName[named] ?? []).isEmpty
    }

    public func hasValues(onConstruct named: String) -> Bool {
        !(valuesByConstructName[named] ?? []).isEmpty
    }

    public func hasInitializers(onConstruct named: String) -> Bool {
        !(initializersByConstructName[named] ?? []).isEmpty
    }
}

public struct DeclarationSyntaxResolver {
    private let protocolsByName: [String: ProtocolDeclaration]
    private let constructsByName: [String: ConstructDeclaration]
    private let extensionsByTargetName: [String: [ExtensionDeclaration]]

    public init(
        protocolsByName: [String: ProtocolDeclaration],
        constructsByName: [String: ConstructDeclaration],
        extensionsByTargetName: [String: [ExtensionDeclaration]]
    ) {
        self.protocolsByName = protocolsByName
        self.constructsByName = constructsByName
        self.extensionsByTargetName = extensionsByTargetName
    }

    public func typeConformsToSyntax(_ typeReference: TypeReference?) -> Bool {
        guard let typeName = nominalName(of: typeReference) else {
            return false
        }
        return declarationIsSyntaxBoundary(named: typeName)
    }

    public func syntaxTypeName(forSurface surfaceName: String) -> String? {
        constructsByName.keys.first {
            declarationIsSyntaxBoundary(named: $0)
                && Self.syntaxSurfaceName(forTypeName: $0) == surfaceName
        }
    }

    public func type(_ typeReference: TypeReference?, matchesSyntaxSurface surfaceName: String) -> Bool {
        guard let typeName = nominalName(of: typeReference),
            let surfaceTypeName = syntaxTypeName(forSurface: surfaceName)
        else {
            return false
        }
        return typeName == surfaceTypeName
            || declaration(named: typeName, conformsTo: surfaceTypeName)
    }

    public func typeConforms(_ typeReference: TypeReference?, to targetProtocol: String) -> Bool {
        guard let typeName = nominalName(of: typeReference) else {
            return false
        }
        return declaration(named: typeName, conformsTo: targetProtocol)
    }

    public func declaration(
        named name: String,
        conformsTo targetProtocol: String
    ) -> Bool {
        declaration(
            named: name,
            conformsTo: targetProtocol,
            visited: []
        )
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
            let extensionConformances = extensionsByTargetName[name, default: []].flatMap(\.conformances)
            return (constructDeclaration.conformances + extensionConformances).contains {
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

    public func declarationIsSyntaxBoundary(named name: String) -> Bool {
        if protocolsByName[name]?.macros.contains(where: { $0.name == "syntax" }) == true {
            return true
        }
        if constructsByName[name]?.macros.contains(where: { $0.name == "syntax" }) == true {
            return true
        }
        return false
    }

    private static func syntaxSurfaceName(forTypeName typeName: String) -> String {
        guard let first = typeName.first else {
            return typeName
        }
        return first.lowercased() + typeName.dropFirst()
    }

    public func nominalName(of typeReference: TypeReference?) -> String? {
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
