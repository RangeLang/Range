import Foundation

extension Parser {
    func isNamespaceDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.namespace.rawValue)
    }

    mutating func parseNamespaceDeclaration(requiresEOF: Bool = true) throws -> NamespaceDeclaration {
        try consumeKeyword(.namespace)
        let name = try consumeTypeName()

        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []

        try consume(.leftBrace)
        while isCallableStart()
            || isConstructDeclarationStart()
            || isBuilderDeclarationStart()
            || isNamespaceDeclarationStart()
        {
            if isCallableStart() {
                callables.append(try parseCallableDeclaration())
                continue
            }
            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                constructs.append(try parseConstructDeclaration(requiresEOF: false))
                continue
            }
            namespaces.append(try parseNamespaceDeclaration(requiresEOF: false))
        }
        try consume(.rightBrace)

        if requiresEOF {
            try consume(.eof)
        }

        try validateCallableDeclarations(callables)

        return NamespaceDeclaration(
            name: name,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces
        )
    }

    mutating func parseNamespaceDeclarationForDeclarationDiscovery() throws -> NamespaceDeclaration {
        try consumeKeyword(.namespace)
        let name = try consumeTypeName()

        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []

        try consume(.leftBrace)
        while isCallableStart()
            || isConstructDeclarationStart()
            || isBuilderDeclarationStart()
            || isNamespaceDeclarationStart()
        {
            if isCallableStart() {
                callables.append(try parseCallableDeclaration(signatureOnly: true))
                continue
            }
            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                constructs.append(try parseConstructDeclarationForDeclarationDiscovery())
                continue
            }
            namespaces.append(try parseNamespaceDeclarationForDeclarationDiscovery())
        }
        try consume(.rightBrace)

        return NamespaceDeclaration(
            name: name,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces
        )
    }
}
