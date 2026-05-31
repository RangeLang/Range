import Foundation

public struct ParsedSourceFile {
    public let path: String
    public let source: String?
    public let sourceFile: SourceFileNode

    public init(path: String, source: String? = nil, sourceFile: SourceFileNode) {
        self.path = path
        self.source = source
        self.sourceFile = sourceFile
    }
}

public enum ApplicationGraphNodeKind: String, Sendable {
    case file
    case construct
    case enumeration
    case protocolDefinition
    case macro
    case typeExtension
    case mainBlock
    case state
    case binding
    case derived
    case value
    case initializer
    case function
    case parameter
    case member
    case typeReference
    case macroApplication

    public var semanticKind: SemanticGraphEntityKind {
        switch self {
        case .file: return .file
        case .construct: return .construct
        case .enumeration: return .enumeration
        case .protocolDefinition: return .protocolDefinition
        case .macro: return .macro
        case .typeExtension: return .typeExtension
        case .mainBlock: return .mainBlock
        case .state: return .state
        case .binding: return .binding
        case .derived: return .derived
        case .value: return .value
        case .initializer: return .initializer
        case .function: return .function
        case .parameter: return .parameter
        case .member: return .member
        case .typeReference: return .typeReference
        case .macroApplication: return .macroApplication
        }
    }
}

public struct ApplicationGraphNode: Hashable {
    public let id: String
    public let kind: ApplicationGraphNodeKind
    public let label: String

    public var semanticKind: SemanticGraphEntityKind {
        kind.semanticKind
    }
}

public enum ApplicationGraphEdgeKind: String {
    case contains
    case conformsTo
    case extends
    case referencesType
    case referencesIdentity
    case appliesMacro
    case targetsMacro
    case resolvesTo
    case dependsOn
    case mutates
    case aliases
    case calls

    public var semanticKind: SemanticGraphRelationKind {
        switch self {
        case .contains: return .contains
        case .conformsTo: return .conformsTo
        case .extends: return .extends
        case .referencesType: return .referencesType
        case .referencesIdentity: return .referencesIdentity
        case .appliesMacro: return .appliesMacro
        case .targetsMacro: return .targetsMacro
        case .resolvesTo: return .resolvesTo
        case .dependsOn: return .dependsOn
        case .mutates: return .mutates
        case .aliases: return .aliases
        case .calls: return .calls
        }
    }
}

public struct ApplicationGraphEdge: Hashable {
    public let sourceID: String
    public let targetID: String
    public let kind: ApplicationGraphEdgeKind

    public var semanticKind: SemanticGraphRelationKind {
        kind.semanticKind
    }
}

public struct ApplicationGraph {
    public let nodes: [ApplicationGraphNode]
    public let edges: [ApplicationGraphEdge]

    public init(nodes: [ApplicationGraphNode], edges: [ApplicationGraphEdge]) {
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
}
