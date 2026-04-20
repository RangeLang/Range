import Foundation

public struct ProtocolDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let conformances: [TypeReference]
    public let states: [StateDeclaration]
    public let bindings: [BindingDeclaration]
    public let deriveds: [DerivedDeclaration]
    public let values: [ValueDeclaration]
    public let initializers: [InitializerDeclaration]
    public let callables: [CallableDeclaration]

    public var isCore: Bool {
        attribute?.name == "core"
    }
}
