import Foundation

public enum SemanticGraphEntityKind: String, Sendable {
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
    case localSymbol
    case unresolved
}

public enum SemanticGraphRelationKind: String, Sendable {
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
}

public struct SemanticGraphEntity: Hashable, Sendable {
    public let id: String
    public let kind: SemanticGraphEntityKind
    public let label: String

    public init(id: String, kind: SemanticGraphEntityKind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}

public struct SemanticGraphRelation: Hashable, Sendable {
    public let sourceID: String
    public let targetID: String
    public let kind: SemanticGraphRelationKind

    public init(sourceID: String, targetID: String, kind: SemanticGraphRelationKind) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
    }
}

public struct ProgramGraphSyntax: Hashable, Sendable {
    public let identity: SemanticGraphEntity
    public let declarations: [SemanticGraphEntity]
    public let applications: [SemanticGraphEntity]

    public init(
        identity: SemanticGraphEntity,
        declarations: [SemanticGraphEntity],
        applications: [SemanticGraphEntity]
    ) {
        self.identity = identity
        self.declarations = declarations.sorted { $0.id < $1.id }
        self.applications = applications.sorted { $0.id < $1.id }
    }
}

public struct ProgramGraph: Sendable {
    public let entities: [SemanticGraphEntity]
    public let relations: [SemanticGraphRelation]
    public let syntax: [ProgramGraphSyntax]

    public init(
        entities: [SemanticGraphEntity],
        relations: [SemanticGraphRelation],
        syntax: [ProgramGraphSyntax] = []
    ) {
        self.entities = entities.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.id < $1.id
        }
        self.relations = relations.sorted {
            if $0.sourceID != $1.sourceID {
                return $0.sourceID < $1.sourceID
            }
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.targetID < $1.targetID
        }
        self.syntax = syntax.sorted {
            if $0.identity.kind.rawValue != $1.identity.kind.rawValue {
                return $0.identity.kind.rawValue < $1.identity.kind.rawValue
            }
            return $0.identity.id < $1.identity.id
        }
    }
}
