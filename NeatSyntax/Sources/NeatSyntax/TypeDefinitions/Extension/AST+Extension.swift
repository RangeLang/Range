import Foundation

public struct ExtensionDeclaration {
    public let macros: [MacroApplication]
    public let targetType: TypeReference
    public let conformances: [TypeReference]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]
    public let enumerations: [EnumDeclaration]
    public let protocols: [ProtocolDeclaration]
}
