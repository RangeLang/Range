import Foundation

public struct OperatorBindingRange: Equatable, Sendable {
    public let lower: Int
    public let upper: Int

    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }
}

public struct PrecedenceMetadataConcept: Equatable, Sendable {
    public let name: String
    public let associativity: OperatorAssociativity?
    public let higherThan: [String]
    public let lowerThan: [String]
    public let assignment: Bool?
    public let step: Int
    public let binding: OperatorBindingRange

    public init(
        name: String,
        associativity: OperatorAssociativity?,
        higherThan: [String],
        lowerThan: [String],
        assignment: Bool?,
        step: Int,
        binding: OperatorBindingRange
    ) {
        self.name = name
        self.associativity = associativity
        self.higherThan = higherThan
        self.lowerThan = lowerThan
        self.assignment = assignment
        self.step = step
        self.binding = binding
    }
}

extension DeclarationGraph {
    public static let precedenceBindingStep = 10

    public var precedenceMetadataConcepts: [PrecedenceMetadataConcept] {
        Self.collectPrecedenceMetadataConcepts(
            from: precedenceGroupsByName,
            step: Self.precedenceBindingStep
        )
    }

    static func collectPrecedenceMetadataConcepts(
        from groupsByName: [String: PrecedenceGroupDeclaration],
        step: Int = precedenceBindingStep
    ) -> [PrecedenceMetadataConcept] {
        var rankMemo: [String: Int] = [:]

        return groupsByName.values.map { group in
            let rank = precedenceRank(
                of: group.name,
                in: groupsByName,
                memo: &rankMemo,
                visiting: []
            )
            let lower = (rank + 1) * step
            return PrecedenceMetadataConcept(
                name: group.name,
                associativity: tokenAssociativity(from: group.associativity),
                higherThan: group.higherThan,
                lowerThan: group.lowerThan,
                assignment: group.assignment,
                step: step,
                binding: OperatorBindingRange(lower: lower, upper: lower + step)
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func precedenceRank(
        of name: String,
        in groupsByName: [String: PrecedenceGroupDeclaration],
        memo: inout [String: Int],
        visiting: Set<String>
    ) -> Int {
        if let cached = memo[name] {
            return cached
        }
        guard let group = groupsByName[name], !visiting.contains(name) else {
            return 0
        }

        let dependencyNames = Set(group.higherThan).union(
            groupsByName.values.compactMap { candidate in
                candidate.lowerThan.contains(name) ? candidate.name : nil
            }
        )
        let rank = dependencyNames.map {
            precedenceRank(
                of: $0,
                in: groupsByName,
                memo: &memo,
                visiting: visiting.union([name])
            ) + 1
        }.max() ?? 0
        memo[name] = rank
        return rank
    }

    private static func tokenAssociativity(
        from associativity: OperatorAssociativity?
    ) -> OperatorAssociativity? {
        associativity
    }
}
