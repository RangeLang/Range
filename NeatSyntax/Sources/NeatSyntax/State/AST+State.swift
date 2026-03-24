import Foundation

public struct StateDeclaration {
    public let name: String
    public let type: BuiltinType
    public let storage: StateStorage
}

public enum StateStorage {
    case stored(Expression)
}

public struct BindingDeclaration {
    public let localName: String
    public let externalLabel: String?
    public let typeName: String
    public let storage: BindingStorage

    public var name: String {
        localName
    }
}

public enum BindingStorage {
    case plain
    case derived(get: [Statement], set: [Statement])
}

public struct EnvironmentDeclaration {
    public let isState: Bool
    public let localName: String
    public let externalLabel: String?
    public let typeName: String

    public var name: String {
        localName
    }
}

public struct EnvironmentProvision {
    public let isState: Bool
    public let name: String
    public let typeName: String
    public let expression: Expression
}

public struct MemberDeclaration {
    public let localName: String
    public let externalLabel: String?
    public let typeName: String
    public let value: Expression?

    public var name: String {
        localName
    }
}
