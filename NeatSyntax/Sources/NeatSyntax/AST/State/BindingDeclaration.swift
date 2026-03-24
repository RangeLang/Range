import Foundation

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
