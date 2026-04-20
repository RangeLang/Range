import Foundation

extension Parser {
    mutating func parseExtensionDeclaration() throws -> ExtensionDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.typeExtension)
        let targetType = try parseTypeReferenceNode()
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        if peek() == .leftBrace {
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
        }
        return ExtensionDeclaration(
            macros: macros,
            targetType: targetType,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces
        )
    }
}
