import Foundation

extension Parser {
    func isNamespaceDeclarationStart() -> Bool {
        peek() == .keyword(GradientSyntax.Keyword.namespace.rawValue)
    }

    mutating func parseNamespaceDeclaration(requiresEOF: Bool = true) throws -> NamespaceDeclaration {
        try consumeKeyword(.namespace)
        let name = try consumeTypeName()

        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var values: [ValueDeclaration] = []

        try consume(.leftBrace)
        while isValueDeclarationStart()
            || isCallableStart()
            || isConstructDeclarationStart()
            || isBuilderDeclarationStart()
            || isNamespaceDeclarationStart()
        {
            if isValueDeclarationStart() {
                values.append(try parseValueDeclaration())
                continue
            }
            if isCallableStart() {
                callables.append(try parseCallableDeclaration())
                continue
            }
            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                let construct = try parseConstructDeclaration(requiresEOF: false)
                if isNamespaceShaped(construct) {
                    namespaces.append(namespaceDeclaration(from: construct))
                } else {
                    constructs.append(construct)
                }
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
            values: values,
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
        var values: [ValueDeclaration] = []

        try consume(.leftBrace)
        while isValueDeclarationStart()
            || isCallableStart()
            || isConstructDeclarationStart()
            || isBuilderDeclarationStart()
            || isNamespaceDeclarationStart()
        {
            if isValueDeclarationStart() {
                values.append(try parseValueDeclaration())
                continue
            }
            if isCallableStart() {
                callables.append(try parseCallableDeclaration(signatureOnly: true))
                continue
            }
            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                let construct = try parseConstructDeclarationForDeclarationDiscovery()
                if isNamespaceShaped(construct) {
                    namespaces.append(namespaceDeclaration(from: construct))
                } else {
                    constructs.append(construct)
                }
                continue
            }
            namespaces.append(try parseNamespaceDeclarationForDeclarationDiscovery())
        }
        try consume(.rightBrace)

        return NamespaceDeclaration(
            name: name,
            values: values,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces
        )
    }

    func namespaceDeclaration(from construct: ConstructDeclaration) -> NamespaceDeclaration {
        NamespaceDeclaration(
            name: construct.name,
            values: construct.values,
            callables: construct.callables,
            constructs: construct.constructs.filter { !isNamespaceShaped($0) },
            namespaces: construct.constructs.filter(isNamespaceShaped).map(namespaceDeclaration(from:))
        )
    }
}
