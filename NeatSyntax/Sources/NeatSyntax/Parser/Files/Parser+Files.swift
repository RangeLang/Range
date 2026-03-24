import Foundation

extension Parser {
    func isMainBlockStart() -> Bool {
        guard case .atAttribute(let name, _) = peek(), name == "main" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    public mutating func parseMainBlock() throws -> MainBlockNode {
        guard case .atAttribute(let name, _) = peek(), name == "main" else {
            throw ParseError("Expected @main block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: [:])
        try consume(.eof)
        return MainBlockNode(body: body)
    }
}
