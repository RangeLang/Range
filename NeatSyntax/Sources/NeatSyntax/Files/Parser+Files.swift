import Foundation

extension Parser {
    func isPackageSpaceStart() -> Bool {
        guard case .atAttribute(let name, _) = peek(), name == "package" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    mutating func parsePackageSpace() throws -> PackageSpaceDeclaration {
        guard case .atAttribute(let name, _) = peek(), name == "package" else {
            throw ParseError("Expected @package block.")
        }
        advance()

        var values: [ValueDeclaration] = []
        var entries: [Expression] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var protocols: [ProtocolDeclaration] = []

        try consume(.leftBrace)
        while isValueDeclarationStart()
            || isCallableStart()
            || isConstructDeclarationStart()
            || isBuilderDeclarationStart()
            || isNamespaceDeclarationStart()
            || isEnumDeclarationStart()
            || isProtocolDeclarationStart()
            || isPackageEntryStart()
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
                constructs.append(try parseConstructDeclaration(requiresEOF: false))
                continue
            }
            if isNamespaceDeclarationStart() {
                namespaces.append(try parseNamespaceDeclaration(requiresEOF: false))
                continue
            }
            if isEnumDeclarationStart() {
                enumerations.append(try parseEnumDeclaration(requiresEOF: false))
                continue
            }
            if isPackageEntryStart() {
                entries.append(try parseExpression(terminatingAt: [.rightBrace]))
                continue
            }
            protocols.append(try parseProtocolDeclaration(requiresEOF: false))
        }
        try consume(.rightBrace)

        try validateCallableDeclarations(callables)

        return PackageSpaceDeclaration(
            values: values,
            entries: entries,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces,
            enumerations: enumerations,
            protocols: protocols
        )
    }

    mutating func parsePackageSpaceForDeclarationDiscovery() throws -> PackageSpaceDeclaration {
        guard case .atAttribute(let name, _) = peek(), name == "package" else {
            throw ParseError("Expected @package block.")
        }
        advance()

        var values: [ValueDeclaration] = []
        var entries: [Expression] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var protocols: [ProtocolDeclaration] = []

        try consume(.leftBrace)
        while isValueDeclarationStart()
            || isCallableStart()
            || isConstructDeclarationStart()
            || isBuilderDeclarationStart()
            || isNamespaceDeclarationStart()
            || isEnumDeclarationStart()
            || isProtocolDeclarationStart()
            || isPackageEntryStart()
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
                constructs.append(try parseConstructDeclarationForDeclarationDiscovery())
                continue
            }
            if isNamespaceDeclarationStart() {
                namespaces.append(try parseNamespaceDeclarationForDeclarationDiscovery())
                continue
            }
            if isEnumDeclarationStart() {
                enumerations.append(try parseEnumDeclaration(requiresEOF: false))
                continue
            }
            if isPackageEntryStart() {
                entries.append(try parseExpression(terminatingAt: [.rightBrace]))
                continue
            }
            protocols.append(try parseProtocolDeclaration(requiresEOF: false))
        }
        try consume(.rightBrace)

        return PackageSpaceDeclaration(
            values: values,
            entries: entries,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces,
            enumerations: enumerations,
            protocols: protocols
        )
    }

    private func isPackageEntryStart() -> Bool {
        switch peek() {
        case .identifier, .keyword:
            return peek(offset: 1) == .leftParen
        default:
            return false
        }
    }

    func isMainBlockStart() -> Bool {
        guard case .hashDirective(let name) = peek(), name == "main" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    public mutating func parseMainBlock(requiresEOF: Bool = true) throws -> MainBlockNode {
        guard case .hashDirective(let name) = peek(), name == "main" else {
            throw ParseError("Expected #main block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: [:])
        if requiresEOF {
            try consume(.eof)
        }
        return MainBlockNode(body: body)
    }
}
