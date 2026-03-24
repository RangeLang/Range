import Foundation

extension Parser {
    mutating func parseExtensionDeclaration() throws -> ExtensionDeclaration {
        try consumeKeyword(.typeExtension)
        let targetName = try consumeTypeReference()
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        return ExtensionDeclaration(targetName: targetName)
    }
}
