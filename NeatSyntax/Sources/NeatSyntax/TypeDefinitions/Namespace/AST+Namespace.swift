import Foundation

public struct NamespaceDeclaration {
    public let name: String
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]

    public init(
        name: String,
        callables: [CallableDeclaration],
        constructs: [ConstructDeclaration],
        namespaces: [NamespaceDeclaration]
    ) {
        self.name = name
        self.callables = callables
        self.constructs = constructs
        self.namespaces = namespaces
    }
}
