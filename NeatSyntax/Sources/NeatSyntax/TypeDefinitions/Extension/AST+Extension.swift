import Foundation

public struct ExtensionDeclaration {
    public let macros: [MacroApplication]
    public let targetType: TypeReference
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]
}
