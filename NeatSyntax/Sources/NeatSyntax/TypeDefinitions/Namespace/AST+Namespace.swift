import Foundation

public struct NamespaceDeclaration {
    public let name: String
    public let values: [ValueDeclaration]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]

    public init(
        name: String,
        values: [ValueDeclaration] = [],
        callables: [CallableDeclaration],
        constructs: [ConstructDeclaration],
        namespaces: [NamespaceDeclaration]
    ) {
        self.name = name
        self.values = values
        self.callables = callables
        self.constructs = constructs
        self.namespaces = namespaces
    }
}
