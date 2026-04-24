import Foundation

extension Parser {
    mutating func parseExtensionDeclaration() throws -> ExtensionDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.typeExtension)
        let targetType = try parseNominalTypeReferenceNode(
            expectedDescription: "Extension target"
        )
        let conformances = try parseConformanceListIfPresent()
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var protocols: [ProtocolDeclaration] = []
        if peek() == .leftBrace {
            try consume(.leftBrace)
            while isCallableStart()
                || isConstructDeclarationStart()
                || isBuilderDeclarationStart()
                || isNamespaceDeclarationStart()
                || isEnumDeclarationStart()
                || isProtocolDeclarationStart()
            {
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
                protocols.append(try parseProtocolDeclaration(requiresEOF: false))
            }
            try consume(.rightBrace)
        }
        return ExtensionDeclaration(
            macros: macros,
            targetType: targetType,
            conformances: conformances,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces,
            enumerations: enumerations,
            protocols: protocols
        )
    }
}
