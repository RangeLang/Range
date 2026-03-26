import Foundation

extension Parser {
    mutating func parseExtensionDeclaration() throws -> ExtensionDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.typeExtension)
        let targetType = try parseTypeReferenceNode()
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return ExtensionDeclaration(macros: macros, targetType: targetType)
    }
}
