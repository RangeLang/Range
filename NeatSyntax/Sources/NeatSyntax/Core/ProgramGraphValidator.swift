import Foundation

public struct ProgramGraphValidator {
    public init() {}

    public func validate(_ graph: ProgramGraph) throws {
        let entityIDs = Set(graph.entities.map(\.id))

        guard entityIDs.count == graph.entities.count else {
            throw SemanticValidationError("ProgramGraph contains duplicate entity IDs.")
        }

        for relation in graph.relations {
            guard entityIDs.contains(relation.sourceID) else {
                throw SemanticValidationError(
                    "ProgramGraph relation '\(relation.kind.rawValue)' has missing source entity '\(relation.sourceID)'."
                )
            }

            guard entityIDs.contains(relation.targetID) else {
                throw SemanticValidationError(
                    "ProgramGraph relation '\(relation.kind.rawValue)' has missing target entity '\(relation.targetID)'."
                )
            }
        }
    }
}
