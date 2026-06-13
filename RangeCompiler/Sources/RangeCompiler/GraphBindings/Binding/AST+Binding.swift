import Foundation

public struct BindingDeclaration {
    public let macros: [MacroApplication]
    public let name: String
    public let typeName: String
    public let storage: BindingStorage
}

public enum BindingStorage {
    case plain
    case derived(get: [Statement], set: [Statement])
}
