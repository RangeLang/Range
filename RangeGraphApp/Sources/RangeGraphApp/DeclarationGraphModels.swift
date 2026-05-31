import Foundation
import RangeSyntax
import SwiftUI

struct DeclarationGraphDocument {
    let title: String
    let sourceRoot: URL?
    let graph: DeclarationGraphSnapshot
}

struct DeclarationGraphSnapshot {
    let nodes: [DeclarationGraphNode]
    let edges: [DeclarationGraphEdge]

    var nodeByID: [String: DeclarationGraphNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    var visibleKinds: [SemanticGraphEntityKind] {
        Array(Set(nodes.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
    }

    var visibleRelationKinds: [SemanticGraphRelationKind] {
        Array(Set(edges.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
    }

    static func from(_ graph: ProgramGraph) -> DeclarationGraphSnapshot {
        DeclarationGraphSnapshot(
            nodes: graph.entities.map(DeclarationGraphNode.init(entity:)),
            edges: graph.relations.map(DeclarationGraphEdge.init(relation:))
        )
    }
}

struct DeclarationGraphNode: Identifiable, Hashable {
    let id: String
    let kind: SemanticGraphEntityKind
    let label: String

    init(entity: SemanticGraphEntity) {
        self.id = entity.id
        self.kind = entity.kind
        self.label = entity.label
    }
}

struct DeclarationGraphEdge: Identifiable, Hashable {
    let sourceID: String
    let targetID: String
    let kind: SemanticGraphRelationKind

    var id: String {
        "\(sourceID)|\(kind.rawValue)|\(targetID)"
    }

    init(relation: SemanticGraphRelation) {
        self.sourceID = relation.sourceID
        self.targetID = relation.targetID
        self.kind = relation.kind
    }

    init(sourceID: String, targetID: String, kind: SemanticGraphRelationKind) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
    }
}

struct PositionedDeclarationNode: Identifiable {
    let node: DeclarationGraphNode
    let position: CGPoint
    let size: CGSize
    let rows: [DeclarationGraphNode]

    var id: String { node.id }
}

enum DeclarationGraphDisplayMode: String, CaseIterable, Identifiable {
    case diagram
    case artistic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diagram:
            return "Diagram"
        case .artistic:
            return "Art"
        }
    }
}

enum DeclarationGraphPalette {
    static let nodeFillByKind: [SemanticGraphEntityKind: Color] = [
        .file: Color(red: 0.30, green: 0.43, blue: 0.55),
        .namespace: Color(red: 0.23, green: 0.54, blue: 0.54),
        .construct: Color(red: 0.74, green: 0.28, blue: 0.22),
        .enumeration: Color(red: 0.60, green: 0.37, blue: 0.24),
        .protocolDefinition: Color(red: 0.39, green: 0.32, blue: 0.48),
        .macro: Color(red: 0.18, green: 0.32, blue: 0.44),
        .typeExtension: Color(red: 0.30, green: 0.57, blue: 0.55),
        .mainBlock: Color(red: 0.86, green: 0.66, blue: 0.22),
        .state: Color(red: 0.70, green: 0.35, blue: 0.15),
        .binding: Color(red: 0.49, green: 0.34, blue: 0.24),
        .derived: Color(red: 0.16, green: 0.58, blue: 0.52),
        .value: Color(red: 0.64, green: 0.34, blue: 0.43),
        .initializer: Color(red: 0.42, green: 0.45, blue: 0.49),
        .function: Color(red: 0.16, green: 0.42, blue: 0.84),
        .parameter: Color(red: 0.51, green: 0.56, blue: 0.64),
        .member: Color(red: 0.34, green: 0.51, blue: 0.34),
        .typeReference: Color(red: 0.62, green: 0.65, blue: 0.68),
        .macroApplication: Color(red: 0.86, green: 0.39, blue: 0.37),
        .localSymbol: Color(red: 0.35, green: 0.38, blue: 0.42),
        .unresolved: Color(red: 0.44, green: 0.44, blue: 0.44),
    ]

    static func fill(for kind: SemanticGraphEntityKind) -> Color {
        nodeFillByKind[kind] ?? .secondary
    }

    static func stroke(for kind: SemanticGraphRelationKind) -> Color {
        switch kind {
        case .contains:
            return Color.secondary.opacity(0.78)
        case .conformsTo, .extends:
            return Color(red: 0.21, green: 0.45, blue: 0.45)
        case .referencesType, .referencesIdentity, .resolvesTo:
            return Color(red: 0.16, green: 0.36, blue: 0.72)
        case .appliesMacro, .targetsMacro:
            return Color(red: 0.72, green: 0.22, blue: 0.28)
        case .dependsOn, .mutates, .aliases, .calls:
            return Color(red: 0.45, green: 0.35, blue: 0.24)
        }
    }
}
