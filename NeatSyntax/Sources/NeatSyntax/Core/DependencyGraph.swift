import Foundation

public struct ParsedSourceFile {
    public let path: String
    public let sourceFile: SourceFileNode

    public init(path: String, sourceFile: SourceFileNode) {
        self.path = path
        self.sourceFile = sourceFile
    }
}

public enum DependencyGraphNodeKind: String {
    case file
    case construct
    case enumeration
    case protocolDefinition
    case macro
    case typeExtension
    case mainBlock
    case state
    case environment
    case binding
    case derived
    case value
    case initializer
    case function
    case parameter
    case typeReference
    case macroApplication
}

public struct DependencyGraphNode: Hashable {
    public let id: String
    public let kind: DependencyGraphNodeKind
    public let label: String
}

public enum DependencyGraphEdgeKind: String {
    case contains
    case conformsTo
    case extends
    case referencesType
    case appliesMacro
    case targetsMacro
}

public struct DependencyGraphEdge: Hashable {
    public let sourceID: String
    public let targetID: String
    public let kind: DependencyGraphEdgeKind
}

public struct DependencyGraph {
    public let nodes: [DependencyGraphNode]
    public let edges: [DependencyGraphEdge]

    public init(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) {
        self.nodes = nodes.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.id < $1.id
        }
        self.edges = edges.sorted {
            if $0.sourceID != $1.sourceID {
                return $0.sourceID < $1.sourceID
            }
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.targetID < $1.targetID
        }
    }

    public func render() -> String {
        let nodeLines = nodes.map { node in
            "[\(node.kind.rawValue)] \(node.id) :: \(node.label)"
        }
        let edgeLines = edges.map { edge in
            "\(edge.sourceID) -\(edge.kind.rawValue)-> \(edge.targetID)"
        }

        return """
            Nodes:
            \(nodeLines.joined(separator: "\n"))

            Edges:
            \(edgeLines.joined(separator: "\n"))
            """
    }
}

public struct DependencyGraphBuilder {
    public init() {}

    public func build(files: [ParsedSourceFile]) -> DependencyGraph {
        var collector = GraphCollector()
        for file in files.sorted(by: { $0.path < $1.path }) {
            collector.add(file)
        }
        return collector.build()
    }
}

private struct GraphCollector {
    private var nodesByID: [String: DependencyGraphNode] = [:]
    private var edges: Set<DependencyGraphEdge> = []

    mutating func build() -> DependencyGraph {
        DependencyGraph(nodes: Array(nodesByID.values), edges: Array(edges))
    }

    mutating func add(_ parsedFile: ParsedSourceFile) {
        let fileID = "file:\(parsedFile.path)"
        addNode(id: fileID, kind: .file, label: parsedFile.path)

        switch parsedFile.sourceFile {
        case .construct(let declaration):
            addConstruct(declaration, parentID: fileID)
        case .enumeration(let declaration):
            addEnum(declaration, parentID: fileID)
        case .protocolDefinition(let declaration):
            addProtocol(declaration, parentID: fileID)
        case .macro(let declaration):
            addMacroDeclaration(declaration, parentID: fileID)
        case .extensions(let declarations):
            for declaration in declarations {
                addExtension(declaration, parentID: fileID)
            }
        case .module(let module):
            for state in module.states {
                addState(state, parentID: fileID)
            }
            for callable in module.callables {
                addCallable(callable, parentID: fileID)
            }
            for declaration in module.constructs {
                addConstruct(declaration, parentID: fileID)
            }
            for declaration in module.enumerations {
                addEnum(declaration, parentID: fileID)
            }
            for declaration in module.protocols {
                addProtocol(declaration, parentID: fileID)
            }
            for declaration in module.macros {
                addMacroDeclaration(declaration, parentID: fileID)
            }
            for declaration in module.extensions {
                addExtension(declaration, parentID: fileID)
            }
        case .mainBlock:
            let mainID = "\(fileID)/main"
            addNode(id: mainID, kind: .mainBlock, label: "@main")
            addEdge(from: fileID, to: mainID, kind: .contains)
        }
    }

    private mutating func addConstruct(_ declaration: ConstructDeclaration, parentID: String) {
        let constructID = "\(parentID)/construct:\(declaration.name)"
        addNode(id: constructID, kind: .construct, label: declaration.name)
        addEdge(from: parentID, to: constructID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: constructID)
        addTypeReferences(declaration.conformances, from: constructID, kind: .conformsTo)

        for state in declaration.states {
            addState(state, parentID: constructID)
        }
        for environment in declaration.environments {
            addEnvironment(environment, parentID: constructID)
        }
        for binding in declaration.bindings {
            addBinding(binding, parentID: constructID)
        }
        for derived in declaration.deriveds {
            addDerived(derived, parentID: constructID)
        }
        for value in declaration.values {
            addValue(value, parentID: constructID)
        }
        for initializer in declaration.initializers {
            addInitializer(initializer, parentID: constructID)
        }
        for callable in declaration.callables {
            addCallable(callable, parentID: constructID)
        }
    }

    private mutating func addEnum(_ declaration: EnumDeclaration, parentID: String) {
        let enumID = "\(parentID)/enum:\(declaration.name)"
        addNode(id: enumID, kind: .enumeration, label: declaration.name)
        addEdge(from: parentID, to: enumID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: enumID)
        addTypeReferences(declaration.conformances, from: enumID, kind: .conformsTo)
    }

    private mutating func addProtocol(_ declaration: ProtocolDeclaration, parentID: String) {
        let protocolID = "\(parentID)/protocol:\(declaration.name)"
        addNode(id: protocolID, kind: .protocolDefinition, label: declaration.name)
        addEdge(from: parentID, to: protocolID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: protocolID)
        addTypeReferences(declaration.conformances, from: protocolID, kind: .conformsTo)
    }

    private mutating func addMacroDeclaration(_ declaration: MacroDeclaration, parentID: String) {
        let macroID = "\(parentID)/macro:\(declaration.name)"
        addNode(id: macroID, kind: .macro, label: declaration.name)
        addEdge(from: parentID, to: macroID, kind: .contains)

        switch declaration.target {
        case .attached(let typeReference), .freestanding(let typeReference):
            addTypeReference(typeReference, from: macroID, kind: .targetsMacro)
        }
    }

    private mutating func addExtension(_ declaration: ExtensionDeclaration, parentID: String) {
        let extensionID = "\(parentID)/extension:\(declaration.targetType.displayName)"
        addNode(
            id: extensionID,
            kind: .typeExtension,
            label: declaration.targetType.displayName
        )
        addEdge(from: parentID, to: extensionID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: extensionID)
        addTypeReference(declaration.targetType, from: extensionID, kind: .extends)
    }

    private mutating func addState(_ declaration: StateDeclaration, parentID: String) {
        let stateID = "\(parentID)/state:\(declaration.name)"
        addNode(id: stateID, kind: .state, label: declaration.name)
        addEdge(from: parentID, to: stateID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: stateID)
    }

    private mutating func addEnvironment(_ declaration: EnvironmentDeclaration, parentID: String) {
        let environmentID = "\(parentID)/environment:\(declaration.name)"
        addNode(id: environmentID, kind: .environment, label: declaration.name)
        addEdge(from: parentID, to: environmentID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: environmentID)
        addTypeReference(.named(declaration.typeName), from: environmentID, kind: .referencesType)
    }

    private mutating func addBinding(_ declaration: BindingDeclaration, parentID: String) {
        let bindingID = "\(parentID)/binding:\(declaration.name)"
        addNode(id: bindingID, kind: .binding, label: declaration.name)
        addEdge(from: parentID, to: bindingID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: bindingID)
        addTypeReference(.named(declaration.typeName), from: bindingID, kind: .referencesType)
    }

    private mutating func addDerived(_ declaration: DerivedDeclaration, parentID: String) {
        let derivedID = "\(parentID)/derived:\(declaration.name)"
        addNode(id: derivedID, kind: .derived, label: declaration.name)
        addEdge(from: parentID, to: derivedID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: derivedID)
        addTypeReference(.named(declaration.typeName), from: derivedID, kind: .referencesType)
        if let builderName = declaration.builderName {
            addTypeReference(.named(builderName), from: derivedID, kind: .referencesType)
        }
    }

    private mutating func addValue(_ declaration: ValueDeclaration, parentID: String) {
        let valueID = "\(parentID)/value:\(declaration.name)"
        addNode(id: valueID, kind: .value, label: declaration.name)
        addEdge(from: parentID, to: valueID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: valueID)
        addTypeReference(.named(declaration.typeName), from: valueID, kind: .referencesType)
    }

    private mutating func addInitializer(
        _ declaration: InitializerDeclaration,
        parentID: String
    ) {
        let initializerID = "\(parentID)/init:\(renderParameterList(declaration.parameters))"
        addNode(id: initializerID, kind: .initializer, label: "init")
        addEdge(from: parentID, to: initializerID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: initializerID)
        for parameter in declaration.parameters {
            addParameter(parameter, parentID: initializerID)
        }
    }

    private mutating func addCallable(_ declaration: CallableDeclaration, parentID: String) {
        let callableID =
            "\(parentID)/function:\(declaration.name)(\(renderParameterList(declaration.parameters)))"
        addNode(id: callableID, kind: .function, label: declaration.name)
        addEdge(from: parentID, to: callableID, kind: .contains)
        addMacroApplications(declaration.macros, parentID: callableID)
        if let targetType = declaration.targetType {
            addTypeReference(targetType, from: callableID, kind: .referencesType)
        }
        if let returnType = declaration.returnType {
            addTypeReference(returnType, from: callableID, kind: .referencesType)
        }
        for parameter in declaration.parameters {
            addParameter(parameter, parentID: callableID)
        }
    }

    private mutating func addParameter(_ parameter: NeatFunctionParameter, parentID: String) {
        let label = parameter.externalLabel ?? "_"
        let parameterID = "\(parentID)/parameter:\(label):\(parameter.localName)"
        addNode(id: parameterID, kind: .parameter, label: parameter.localName)
        addEdge(from: parentID, to: parameterID, kind: .contains)
        addMacroApplications(parameter.macros, parentID: parameterID)
        if let typeReference = parameter.typeReference {
            addTypeReference(typeReference, from: parameterID, kind: .referencesType)
        }
    }

    private mutating func addMacroApplications(
        _ macros: [MacroApplication],
        parentID: String
    ) {
        for macro in macros {
            let macroID = "\(parentID)/macro-application:#\(macro.name)"
            addNode(id: macroID, kind: .macroApplication, label: "#\(macro.name)")
            addEdge(from: parentID, to: macroID, kind: .appliesMacro)
        }
    }

    private mutating func addTypeReferences(
        _ references: [TypeReference],
        from sourceID: String,
        kind: DependencyGraphEdgeKind
    ) {
        for reference in references {
            addTypeReference(reference, from: sourceID, kind: kind)
        }
    }

    private mutating func addTypeReference(
        _ reference: TypeReference,
        from sourceID: String,
        kind: DependencyGraphEdgeKind
    ) {
        let typeID = "type:\(reference.displayName)"
        addNode(id: typeID, kind: .typeReference, label: reference.displayName)
        addEdge(from: sourceID, to: typeID, kind: kind)
    }

    private mutating func addNode(id: String, kind: DependencyGraphNodeKind, label: String) {
        nodesByID[id] = DependencyGraphNode(id: id, kind: kind, label: label)
    }

    private mutating func addEdge(
        from sourceID: String, to targetID: String, kind: DependencyGraphEdgeKind
    ) {
        edges.insert(DependencyGraphEdge(sourceID: sourceID, targetID: targetID, kind: kind))
    }

    private func renderParameterList(_ parameters: [NeatFunctionParameter]) -> String {
        parameters.map { parameter in
            let typeName =
                parameter.slotName.map { "@\($0)" } ?? parameter.typeReference?.displayName
                ?? "_"
            let label = parameter.externalLabel ?? "_"
            return "\(label):\(typeName)"
        }.joined(separator: ",")
    }
}
