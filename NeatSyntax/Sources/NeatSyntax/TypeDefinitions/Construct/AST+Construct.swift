import Foundation

public enum ConstructKind {
    case entry
    case declaration
    case builder
}

public struct ConstructDeclaration {
    public let macros: [MacroApplication]
    public let kind: ConstructKind
    public let attribute: AttributeApplication?
    public let name: String
    public let conformances: [TypeReference]
    public let states: [StateDeclaration]
    public let environments: [EnvironmentDeclaration]
    public let bindings: [BindingDeclaration]
    public let deriveds: [DerivedDeclaration]
    public let values: [ValueDeclaration]
    public let initializers: [InitializerDeclaration]
    public let callables: [CallableDeclaration]

    public var isCore: Bool {
        attribute?.name == "core"
    }
}

public struct AttributeApplication {
    public let name: String
    public let argument: String?
}
