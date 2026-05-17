import Foundation

public struct DeclarationGraphValidator: CompiledProgramValidationPass {
    public let name = "DeclarationGraph"

    public init() {}

    public func validate(_ program: CompiledProgram) throws {
        try validateAttributeUsage(
            in: program.projectParsedFiles,
            declarationGraph: program.declarationGraph
        )
        try validatePrimaryDeclarations(in: program.parsedFiles)
        try validateTopLevelStates(in: program.parsedFiles)
        try validateProtocolConformances(in: program.declarationGraph)
    }

    public func validatePrimaryDeclarations(in program: CompiledProgram) throws {
        try validatePrimaryDeclarations(in: program.expandedFiles)
    }

    private func validatePrimaryDeclarations(in parsedFiles: [ParsedSourceFile]) throws {
        var firstDeclarationByName: [String: String] = [:]

        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) {
                if let firstPath = firstDeclarationByName[declaration.name] {
                    throw SemanticValidationError(
                        "Duplicate primary declaration #\(declaration.name) in \(lastPathComponent(of: parsedFile.path)). First declared in \(lastPathComponent(of: firstPath)). Use extension \(declaration.name) to augment an existing declaration."
                    )
                }

                firstDeclarationByName[declaration.name] = parsedFile.path
            }
        }
    }

    private func validateTopLevelStates(in parsedFiles: [ParsedSourceFile]) throws {
        var firstStateByName: [String: String] = [:]

        for parsedFile in parsedFiles {
            for state in topLevelStates(in: parsedFile.sourceFile) {
                if let firstPath = firstStateByName[state.name] {
                    throw SemanticValidationError(
                        "Duplicate top-level state \(state.name) in \(lastPathComponent(of: parsedFile.path)). First declared in \(lastPathComponent(of: firstPath))."
                    )
                }

                firstStateByName[state.name] = parsedFile.path
            }
        }
    }

    private func validateProtocolConformances(in declarationGraph: DeclarationGraph) throws {
        for construct in declarationGraph.constructsByName.values {
            try validateProtocolConformances(
                of: construct,
                declarationGraph: declarationGraph
            )
        }
        for extensions in declarationGraph.extensionsByTargetName.values {
            for declaration in extensions {
                try validateProtocolConformances(
                    of: declaration,
                    declarationGraph: declarationGraph
                )
            }
        }
    }

    private func validateProtocolConformances(
        of construct: ConstructDeclaration,
        declarationGraph: DeclarationGraph
    ) throws {
        for conformance in declarationGraph.conformances(onConstruct: construct.name) {
            guard let protocolName = protocolName(for: conformance),
                let protocolDeclaration = declarationGraph.protocolsByName[protocolName]
            else {
                continue
            }

            if skipsExplicitRequirementValidation(
                for: construct,
                protocol: protocolDeclaration
            ) {
                continue
            }

            let substitution = genericSubstitution(
                for: protocolDeclaration,
                conformance: conformance
            )
            let requirements = collectedRequirements(
                of: protocolDeclaration,
                declarationGraph: declarationGraph,
                visitedProtocols: []
            ).substituted(using: substitution)

            try validateValueRequirements(
                requirements.values,
                on: construct,
                protocolName: protocolName
            )
            try validateStateRequirements(
                requirements.states,
                on: construct,
                protocolName: protocolName
            )
            try validateBindingRequirements(
                requirements.bindings,
                on: construct,
                protocolName: protocolName
            )
            try validateDerivedRequirements(
                requirements.deriveds,
                on: construct,
                protocolName: protocolName
            )
            try validateInitializerRequirements(
                requirements.initializers,
                onConstructNamed: construct.name,
                protocolName: protocolName,
                declarationGraph: declarationGraph
            )
            try validateCallableRequirements(
                requirements.callables,
                on: construct,
                protocolName: protocolName,
                declarationGraph: declarationGraph
            )
        }
    }

    private func validateProtocolConformances(
        of declaration: ExtensionDeclaration,
        declarationGraph: DeclarationGraph
    ) throws {
        guard let construct = declarationGraph.construct(named: declaration.targetName) else {
            return
        }

        for conformance in declaration.conformances {
            guard let protocolName = protocolName(for: conformance),
                let protocolDeclaration = declarationGraph.protocolsByName[protocolName]
            else {
                continue
            }

            if skipsExplicitRequirementValidation(
                for: construct,
                protocol: protocolDeclaration
            ) {
                continue
            }

            let substitution = genericSubstitution(
                for: protocolDeclaration,
                conformance: conformance
            )
            let requirements = collectedRequirements(
                of: protocolDeclaration,
                declarationGraph: declarationGraph,
                visitedProtocols: []
            ).substituted(using: substitution)

            try validateValueRequirements(
                requirements.values,
                on: construct,
                protocolName: protocolName
            )
            try validateStateRequirements(
                requirements.states,
                on: construct,
                protocolName: protocolName
            )
            try validateBindingRequirements(
                requirements.bindings,
                on: construct,
                protocolName: protocolName
            )
            try validateDerivedRequirements(
                requirements.deriveds,
                on: construct,
                protocolName: protocolName
            )
            try validateInitializerRequirements(
                requirements.initializers,
                onConstructNamed: construct.name,
                protocolName: protocolName,
                declarationGraph: declarationGraph
            )
            try validateCallableRequirements(
                requirements.callables,
                on: construct,
                protocolName: protocolName,
                declarationGraph: declarationGraph
            )
        }
    }

    private func skipsExplicitRequirementValidation(
        for construct: ConstructDeclaration,
        protocol protocolDeclaration: ProtocolDeclaration
    ) -> Bool {
        guard construct.isCore else {
            return false
        }

        return synthesizedCoreProtocols.contains(protocolDeclaration.name)
    }

    private func collectedRequirements(
        of declaration: ProtocolDeclaration,
        declarationGraph: DeclarationGraph,
        visitedProtocols: Set<String>
    ) -> ProtocolRequirements {
        guard !visitedProtocols.contains(declaration.name) else {
            return ProtocolRequirements()
        }

        let nextVisited = visitedProtocols.union([declaration.name])
        var requirements = ProtocolRequirements(
            states: declaration.states,
            bindings: declaration.bindings,
            deriveds: declaration.deriveds,
            values: declaration.values,
            initializers: declaration.initializers,
            callables: declaration.callables
        )

        for conformance in declaration.conformances {
            guard let protocolName = protocolName(for: conformance),
                let inherited = declarationGraph.protocolsByName[protocolName]
            else {
                continue
            }

            let substitution = genericSubstitution(
                for: inherited,
                conformance: conformance
            )
            let inheritedRequirements = collectedRequirements(
                of: inherited,
                declarationGraph: declarationGraph,
                visitedProtocols: nextVisited
            ).substituted(using: substitution)
            requirements.merge(inheritedRequirements)
        }

        return requirements
    }

    private func validateValueRequirements(
        _ requirements: [ValueDeclaration],
        on construct: ConstructDeclaration,
        protocolName: String
    ) throws {
        for requirement in requirements {
            guard
                construct.values.contains(where: {
                    $0.name == requirement.name && $0.typeName == requirement.typeName
                })
            else {
                throw SemanticValidationError(
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing let \(requirement.name): \(requirement.typeName)."
                )
            }
        }
    }

    private func validateStateRequirements(
        _ requirements: [StateDeclaration],
        on construct: ConstructDeclaration,
        protocolName: String
    ) throws {
        for requirement in requirements {
            guard
                construct.states.contains(where: {
                    $0.name == requirement.name
                        && $0.type.displayName == requirement.type.displayName
                })
            else {
                throw SemanticValidationError(
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing state \(requirement.name): \(requirement.type.displayName)."
                )
            }
        }
    }

    private func validateBindingRequirements(
        _ requirements: [BindingDeclaration],
        on construct: ConstructDeclaration,
        protocolName: String
    ) throws {
        for requirement in requirements {
            guard
                construct.bindings.contains(where: {
                    $0.name == requirement.name && $0.typeName == requirement.typeName
                })
            else {
                throw SemanticValidationError(
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing binding \(requirement.name): \(requirement.typeName)."
                )
            }
        }
    }

    private func validateDerivedRequirements(
        _ requirements: [DerivedDeclaration],
        on construct: ConstructDeclaration,
        protocolName: String
    ) throws {
        for requirement in requirements {
            guard
                construct.deriveds.contains(where: {
                    $0.name == requirement.name && $0.typeName == requirement.typeName
                })
            else {
                throw SemanticValidationError(
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing derived \(requirement.name): \(requirement.typeName)."
                )
            }
        }
    }

    private func validateInitializerRequirements(
        _ requirements: [InitializerDeclaration],
        onConstructNamed constructName: String,
        protocolName: String,
        declarationGraph: DeclarationGraph
    ) throws {
        let availableInitializers = declarationGraph.initializers(onConstruct: constructName)
        for requirement in requirements {
            guard
                availableInitializers.contains(where: {
                    initializerMatchesRequirement($0, requirement: requirement)
                })
            else {
                throw SemanticValidationError(
                    "Construct \(constructName) does not satisfy protocol \(protocolName): missing initializer \(renderInitializerSignature(requirement))."
                )
            }
        }
    }

    private func validateCallableRequirements(
        _ requirements: [CallableDeclaration],
        on construct: ConstructDeclaration,
        protocolName: String,
        declarationGraph: DeclarationGraph
    ) throws {
        let availableCallables = declarationGraph.callables(onConstruct: construct.name)
        for requirement in requirements {
            guard
                availableCallables.contains(where: {
                    callableMatchesRequirement($0, requirement: requirement)
                })
            else {
                throw SemanticValidationError(
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing function \(renderCallableSignature(requirement))."
                )
            }
        }
    }

    private func initializerMatchesRequirement(
        _ candidate: InitializerDeclaration,
        requirement: InitializerDeclaration
    ) -> Bool {
        candidate.parameters.count == requirement.parameters.count
            && zip(candidate.parameters, requirement.parameters).allSatisfy { candidate, requirement in
                labelsMatch(candidate.externalLabel, requirement.externalLabel)
                    && candidate.typeReference?.displayName == requirement.typeReference?.displayName
            }
            && candidate.returnType?.displayName == requirement.returnType?.displayName
    }

    private func callableMatchesRequirement(
        _ candidate: CallableDeclaration,
        requirement: CallableDeclaration
    ) -> Bool {
        candidate.name == requirement.name
            && candidate.parameters.count == requirement.parameters.count
            && candidate.returnType?.displayName == requirement.returnType?.displayName
            && zip(candidate.parameters, requirement.parameters).allSatisfy { candidate, requirement in
                labelsMatch(candidate.externalLabel, requirement.externalLabel)
                    && candidate.typeReference?.displayName == requirement.typeReference?.displayName
            }
    }

    private func labelsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        normalizeLabel(lhs) == normalizeLabel(rhs)
    }

    private func normalizeLabel(_ label: String?) -> String? {
        switch label {
        case nil, "_":
            return nil
        case .some(let value):
            return value
        }
    }

    private func renderInitializerSignature(_ declaration: InitializerDeclaration) -> String {
        let parameters = declaration.parameters.map(renderParameterRequirement).joined(separator: ", ")
        if let returnType = declaration.returnType?.displayName {
            return "init(\(parameters)) -> \(returnType)"
        }
        return "init(\(parameters))"
    }

    private func renderCallableSignature(_ declaration: CallableDeclaration) -> String {
        let parameters = declaration.parameters.map(renderParameterRequirement).joined(separator: ", ")
        if let returnType = declaration.returnType?.displayName {
            return "\(declaration.name)(\(parameters)) -> \(returnType)"
        }
        return "\(declaration.name)(\(parameters))"
    }

    private func renderParameterRequirement(_ parameter: NeatFunctionParameter) -> String {
        let label = parameter.externalLabel ?? "_"
        let typeName = parameter.typeReference?.displayName ?? "_"
        return "\(label): \(typeName)"
    }

    private func protocolName(for conformance: TypeReference) -> String? {
        switch conformance {
        case .named(let name):
            return name
        case .generic(let base, _):
            return protocolName(for: base)
        case .member, .array, .function, .optional, .variadic:
            return nil
        }
    }

    private func genericSubstitution(
        for protocolDeclaration: ProtocolDeclaration,
        conformance: TypeReference
    ) -> [String: TypeReference] {
        let parameterNames = protocolDeclaration.genericParameters.compactMap { parameter -> String? in
            guard case .type(let name, _, _) = parameter else {
                return nil
            }
            return name
        }

        guard !parameterNames.isEmpty else {
            return [:]
        }

        guard case .generic(_, let arguments) = conformance,
            arguments.count == parameterNames.count
        else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: zip(parameterNames, arguments))
    }

    private func validateAttributeUsage(
        in parsedFiles: [ParsedSourceFile],
        declarationGraph: DeclarationGraph
    ) throws {
        for parsedFile in parsedFiles {
            for declaration in attributedConstructs(in: parsedFile.sourceFile) {
                try validateAttribute(
                    declaration.attribute,
                    declarationName: declaration.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
            }
            for callable in callables(in: parsedFile.sourceFile) {
                try validateAttribute(
                    callable.attribute,
                    declarationName: callable.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
            }
            for declaration in protocols(in: parsedFile.sourceFile) {
                try validateAttribute(
                    declaration.attribute,
                    declarationName: declaration.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
            }
            for declaration in enumerations(in: parsedFile.sourceFile) {
                try validateAttribute(
                    declaration.attribute,
                    declarationName: declaration.name,
                    filePath: parsedFile.path,
                    declarationGraph: declarationGraph
                )
            }
        }
    }

    private func validateAttribute(
        _ attribute: AttributeApplication?,
        declarationName: String,
        filePath: String,
        declarationGraph: DeclarationGraph
    ) throws {
        guard let attribute else {
            return
        }

        if attribute.isLanguageBoundary {
            throw SemanticValidationError(
                "@language can only be used in NeatCore. Remove @language from \(declarationName) in \(lastPathComponent(of: filePath))."
            )
        }

        guard NeatSyntax.attributeIdentifiers.contains(attribute.name)
            || declarationGraph.hasNamespaceAttribute(named: attribute.name)
        else {
            throw SemanticValidationError(
                "Unknown attribute @\(attribute.name) in \(lastPathComponent(of: filePath)). Declare namespace \(attribute.name) to use @\(attribute.name)."
            )
        }
    }

    private func attributedConstructs(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration] + declaration.constructs.flatMap {
                attributedConstructs(in: .construct($0))
            }
        case .namespace(let declaration):
            return declaration.constructs.flatMap { attributedConstructs(in: .construct($0)) }
                + declaration.namespaces.flatMap { attributedConstructs(in: .namespace($0)) }
        case .module(let module):
            return module.constructs.flatMap { attributedConstructs(in: .construct($0)) }
                + module.namespaces.flatMap { attributedConstructs(in: .namespace($0)) }
                + module.extensions.flatMap { attributedConstructs(in: $0) }
        case .extensions(let declarations):
            return declarations.flatMap { attributedConstructs(in: $0) }
        case .mainBlock, .enumeration, .protocolDefinition, .macro, .marker:
            return []
        }
    }

    private func attributedConstructs(in declaration: ExtensionDeclaration) -> [ConstructDeclaration] {
        declaration.constructs.flatMap { attributedConstructs(in: .construct($0)) }
            + declaration.namespaces.flatMap { attributedConstructs(in: .namespace($0)) }
    }

    private func declarations(in declaration: ExtensionDeclaration) -> [ConstructDeclaration] {
        declaration.constructs + declaration.constructs.flatMap { declarations(in: .construct($0)) }
            + declaration.namespaces.flatMap { declarations(in: .namespace($0)) }
    }

    private func callables(in declaration: ExtensionDeclaration) -> [CallableDeclaration] {
        declaration.callables
            + declaration.constructs.flatMap { $0.callables }
            + declaration.namespaces.flatMap { callables(in: .namespace($0)) }
    }

    private func protocols(in declaration: ExtensionDeclaration) -> [ProtocolDeclaration] {
        declaration.protocols
            + declaration.namespaces.flatMap { protocols(in: .namespace($0)) }
    }

    private func enumerations(in declaration: ExtensionDeclaration) -> [EnumDeclaration] {
        declaration.enumerations
            + declaration.namespaces.flatMap { enumerations(in: .namespace($0)) }
    }

    private func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .namespace(let declaration):
            return declaration.constructs + declaration.namespaces.flatMap { declarations(in: .namespace($0)) }
        case .module(let module):
            return module.constructs + module.namespaces.flatMap { declarations(in: .namespace($0)) }
        case .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro, .marker:
            return []
        }
    }

    private func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .namespace, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro, .marker:
            return []
        }
    }

    private func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables + module.namespaces.flatMap { callables(in: .namespace($0)) }
                + module.constructs.flatMap { callables(in: .construct($0)) }
                + module.extensions.flatMap { callables(in: $0) }
        case .namespace(let declaration):
            return declaration.callables + declaration.namespaces.flatMap { callables(in: .namespace($0)) }
                + declaration.constructs.flatMap { callables(in: .construct($0)) }
        case .construct(let declaration):
            return declaration.callables + declaration.constructs.flatMap { callables(in: .construct($0)) }
        case .extensions(let declarations):
            return declarations.flatMap { callables(in: $0) }
        case .mainBlock, .enumeration, .protocolDefinition, .macro, .marker:
            return []
        }
    }

    private func protocols(in sourceFile: SourceFileNode) -> [ProtocolDeclaration] {
        switch sourceFile {
        case .protocolDefinition(let declaration):
            return [declaration]
        case .module(let module):
            return module.protocols + module.extensions.flatMap { protocols(in: $0) }
        case .extensions(let declarations):
            return declarations.flatMap { protocols(in: $0) }
        case .construct, .namespace, .mainBlock, .enumeration, .macro, .marker:
            return []
        }
    }

    private func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let declaration):
            return [declaration]
        case .module(let module):
            return module.enumerations + module.extensions.flatMap { enumerations(in: $0) }
        case .extensions(let declarations):
            return declarations.flatMap { enumerations(in: $0) }
        case .construct, .namespace, .mainBlock, .protocolDefinition, .macro, .marker:
            return []
        }
    }

    private func lastPathComponent(of path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct ProtocolRequirements {
    var states: [StateDeclaration] = []
    var bindings: [BindingDeclaration] = []
    var deriveds: [DerivedDeclaration] = []
    var values: [ValueDeclaration] = []
    var initializers: [InitializerDeclaration] = []
    var callables: [CallableDeclaration] = []

    mutating func merge(_ other: ProtocolRequirements) {
        states.append(contentsOf: other.states)
        bindings.append(contentsOf: other.bindings)
        deriveds.append(contentsOf: other.deriveds)
        values.append(contentsOf: other.values)
        initializers.append(contentsOf: other.initializers)
        callables.append(contentsOf: other.callables)
    }

    func substituted(using bindings: [String: TypeReference]) -> ProtocolRequirements {
        guard !bindings.isEmpty else {
            return self
        }

        return ProtocolRequirements(
            states: states.map { $0.substituted(using: bindings) },
            bindings: self.bindings.map { $0.substituted(using: bindings) },
            deriveds: deriveds.map { $0.substituted(using: bindings) },
            values: values.map { $0.substituted(using: bindings) },
            initializers: initializers.map { $0.substituted(using: bindings) },
            callables: callables.map { $0.substituted(using: bindings) }
        )
    }
}

private extension ValueDeclaration {
    func substituted(using bindings: [String: TypeReference]) -> ValueDeclaration {
        ValueDeclaration(
            macros: macros,
            localName: localName,
            externalLabel: externalLabel,
            typeName: substituteTypeName(typeName, using: bindings),
            value: value
        )
    }
}

private extension BindingDeclaration {
    func substituted(using bindings: [String: TypeReference]) -> BindingDeclaration {
        BindingDeclaration(
            macros: macros,
            localName: localName,
            externalLabel: externalLabel,
            typeName: substituteTypeName(typeName, using: bindings),
            storage: storage
        )
    }
}

private extension DerivedDeclaration {
    func substituted(using bindings: [String: TypeReference]) -> DerivedDeclaration {
        DerivedDeclaration(
            macros: macros,
            builderName: builderName,
            name: name,
            typeName: substituteTypeName(typeName, using: bindings),
            body: body
        )
    }
}

private extension StateDeclaration {
    func substituted(using bindings: [String: TypeReference]) -> StateDeclaration {
        StateDeclaration(
            macros: macros,
            name: name,
            hasExplicitTypeAnnotation: hasExplicitTypeAnnotation,
            type: substitute(type, using: bindings),
            storage: storage
        )
    }
}

private extension InitializerDeclaration {
    func substituted(using bindings: [String: TypeReference]) -> InitializerDeclaration {
        InitializerDeclaration(
            macros: macros,
            parameters: parameters.map { $0.substituted(using: bindings) },
            returnType: returnType.map { substitute($0, using: bindings) },
            body: body
        )
    }
}

private extension CallableDeclaration {
    func substituted(using bindings: [String: TypeReference]) -> CallableDeclaration {
        CallableDeclaration(
            macros: macros,
            attribute: attribute,
            targetType: targetType.map { substitute($0, using: bindings) },
            receiverType: receiverType.map { substitute($0, using: bindings) },
            name: name,
            genericParameters: genericParameters,
            hasExplicitParameterClause: hasExplicitParameterClause,
            parameters: parameters.map { $0.substituted(using: bindings) },
            returnType: returnType.map { substitute($0, using: bindings) },
            body: body
        )
    }
}

private extension NeatFunctionParameter {
    func substituted(using bindings: [String: TypeReference]) -> NeatFunctionParameter {
        NeatFunctionParameter(
            macros: macros,
            localName: localName,
            externalLabel: externalLabel,
            typeReference: typeReference.map { substitute($0, using: bindings) },
            defaultValue: defaultValue,
            slotName: slotName,
            isBinding: isBinding,
            capturesSyntax: capturesSyntax
        )
    }
}

private func substituteTypeName(_ typeName: String, using bindings: [String: TypeReference]) -> String {
    bindings[typeName]?.displayName ?? typeName
}

private func substitute(_ type: TypeReference, using bindings: [String: TypeReference]) -> TypeReference {
    switch type {
    case .named(let name):
        return bindings[name] ?? type
    case .member(let base, let name):
        return .member(base: substitute(base, using: bindings), name: name)
    case .generic(let base, let arguments):
        return .generic(
            base: substitute(base, using: bindings),
            arguments: arguments.map { substitute($0, using: bindings) }
        )
    case .array(let element):
        return .array(substitute(element, using: bindings))
    case .function(let parameters, let returnType):
        return .function(
            parameters: parameters.map { substitute($0, using: bindings) },
            returnType: substitute(returnType, using: bindings)
        )
    case .optional(let wrapped):
        return .optional(substitute(wrapped, using: bindings))
    case .variadic(let element):
        return .variadic(substitute(element, using: bindings))
    }
}

private let synthesizedCoreProtocols: Set<String> = [
    "Equatable",
    "Comparable",
    "Hashable",
    "SupportsExtension",
]
