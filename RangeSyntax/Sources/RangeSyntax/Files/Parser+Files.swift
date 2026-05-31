import Foundation

extension Parser {
    func isMainBlockStart() -> Bool {
        guard case .macroAttribute(let name, nil) = peek(), name == "main" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    public mutating func parseMainBlock(requiresEOF: Bool = true) throws -> MainBlockNode {
        guard case .macroAttribute(let name, nil) = peek(), name == "main" else {
            throw ParseError("Expected @main block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: [:])
        if requiresEOF {
            try consume(.eof)
        }
        return MainBlockNode(body: body)
    }
}
