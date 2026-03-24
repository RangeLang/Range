import Foundation

public struct StateDeclaration {
    public let name: String
    public let type: BuiltinType
    public let storage: StateStorage
}

public enum StateStorage {
    case stored(Expression)
}
