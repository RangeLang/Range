import Foundation

public enum OperatorFixity: String {
    case prefix
    case infix
    case postfix
}

public enum OperatorAssociativity: String {
    case none
    case left
    case right
}

public struct PrecedenceGroupDeclaration {
    public let name: String
    public let associativity: OperatorAssociativity?
    public let higherThan: [String]
    public let lowerThan: [String]
    public let assignment: Bool?

    public init(
        name: String,
        associativity: OperatorAssociativity?,
        higherThan: [String],
        lowerThan: [String],
        assignment: Bool?
    ) {
        self.name = name
        self.associativity = associativity
        self.higherThan = higherThan
        self.lowerThan = lowerThan
        self.assignment = assignment
    }
}

public struct OperatorDeclaration {
    public let fixity: OperatorFixity
    public let symbol: String
    public let precedenceGroup: String?

    public init(fixity: OperatorFixity, symbol: String, precedenceGroup: String?) {
        self.fixity = fixity
        self.symbol = symbol
        self.precedenceGroup = precedenceGroup
    }
}
