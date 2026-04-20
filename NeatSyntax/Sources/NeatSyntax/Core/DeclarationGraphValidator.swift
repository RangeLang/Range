import Foundation

public struct DeclarationGraphValidator: CompiledProgramValidationPass {
    public let name = "DeclarationGraph"

    public init() {}

    public func validate(_ program: CompiledProgram) throws {
        try validateCoreAttributeUsage(in: program.projectParsedFiles)
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
    }

    private func validateProtocolConformances(
        of construct: ConstructDeclaration,
        declarationGraph: DeclarationGraph
    ) throws {
        for conformance in construct.conformances {
            guard case .named(let protocolName) = conformance,
                let protocolDeclaration = declarationGraph.protocolsByName[protocolName]
            else {
                continue
            }

            let requirements = collectedRequirements(
                of: protocolDeclaration,
                declarationGraph: declarationGraph,
                visitedProtocols: []
            )

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
                on: construct,
                protocolName: protocolName
            )
            try validateCallableRequirements(
                requirements.callables,
                on: construct,
                protocolName: protocolName
            )
        }
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
            guard case .named(let protocolName) = conformance,
                let inherited = declarationGraph.protocolsByName[protocolName]
            else {
                continue
            }

            let inheritedRequirements = collectedRequirements(
                of: inherited,
                declarationGraph: declarationGraph,
                visitedProtocols: nextVisited
            )
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
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing value \(requirement.name): \(requirement.typeName)."
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
        on construct: ConstructDeclaration,
        protocolName: String
    ) throws {
        for requirement in requirements {
            guard
                construct.initializers.contains(where: {
                    initializerMatchesRequirement($0, requirement: requirement)
                })
            else {
                throw SemanticValidationError(
                    "Construct \(construct.name) does not satisfy protocol \(protocolName): missing initializer \(renderInitializerSignature(requirement))."
                )
            }
        }
    }

    private func validateCallableRequirements(
        _ requirements: [CallableDeclaration],
        on construct: ConstructDeclaration,
        protocolName: String
    ) throws {
        for requirement in requirements {
            guard
                construct.callables.contains(where: {
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
                candidate.externalLabel == requirement.externalLabel
                    && candidate.typeReference?.displayName == requirement.typeReference?.displayName
            }
    }

    private func callableMatchesRequirement(
        _ candidate: CallableDeclaration,
        requirement: CallableDeclaration
    ) -> Bool {
        candidate.name == requirement.name
            && candidate.parameters.count == requirement.parameters.count
            && candidate.returnType?.displayName == requirement.returnType?.displayName
            && zip(candidate.parameters, requirement.parameters).allSatisfy { candidate, requirement in
                candidate.externalLabel == requirement.externalLabel
                    && candidate.typeReference?.displayName == requirement.typeReference?.displayName
            }
    }

    private func renderInitializerSignature(_ declaration: InitializerDeclaration) -> String {
        "init(\(declaration.parameters.map(renderParameterRequirement).joined(separator: ", ")))"
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

    private func validateCoreAttributeUsage(in parsedFiles: [ParsedSourceFile]) throws {
        for parsedFile in parsedFiles {
            for declaration in declarations(in: parsedFile.sourceFile) where declaration.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(declaration.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
            for callable in callables(in: parsedFile.sourceFile) where callable.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(callable.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
            for declaration in protocols(in: parsedFile.sourceFile) where declaration.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(declaration.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
            for declaration in enumerations(in: parsedFile.sourceFile) where declaration.isCore {
                throw SemanticValidationError(
                    "@core can only be used in NeatCore. Remove @core from \(declaration.name) in \(lastPathComponent(of: parsedFile.path))."
                )
            }
        }
    }

    private func declarations(in sourceFile: SourceFileNode) -> [ConstructDeclaration] {
        switch sourceFile {
        case .construct(let declaration):
            return [declaration]
        case .module(let module):
            return module.constructs
        case .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func topLevelStates(in sourceFile: SourceFileNode) -> [StateDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.states
        case .construct, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func callables(in sourceFile: SourceFileNode) -> [CallableDeclaration] {
        switch sourceFile {
        case .module(let module):
            return module.callables
        case .construct, .mainBlock, .extensions, .enumeration, .protocolDefinition, .macro:
            return []
        }
    }

    private func protocols(in sourceFile: SourceFileNode) -> [ProtocolDeclaration] {
        switch sourceFile {
        case .protocolDefinition(let declaration):
            return [declaration]
        case .module(let module):
            return module.protocols
        case .construct, .mainBlock, .extensions, .enumeration, .macro:
            return []
        }
    }

    private func enumerations(in sourceFile: SourceFileNode) -> [EnumDeclaration] {
        switch sourceFile {
        case .enumeration(let declaration):
            return [declaration]
        case .module(let module):
            return module.enumerations
        case .construct, .mainBlock, .extensions, .protocolDefinition, .macro:
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
}
