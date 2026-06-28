import Foundation

extension Parser {
    mutating func parseStatement() throws -> Statement {
        if isMacroApplicationStart() {
            return try parseMacroApplicationStatement()
        }

        throw ParseError("Expected statement, found \(peek()).")
    }

    mutating func parseMacroApplicationStatement() throws -> Statement {
        guard case .macroAttribute(let name, _) = peek() else {
            throw ParseError("Expected macro application statement.")
        }
        advance()
        if peek() == .leftBrace {
            return .macroInvocation(
                name: name,
                argumentClause: nil,
                body: try parseStatementBlock()
            )
        }
        if macroArgumentClauseIsFollowedByBlock() {
            let argumentClause = try parseMacroArgumentClauseIfPresent()
            return .macroInvocation(
                name: name,
                argumentClause: argumentClause,
                body: try parseStatementBlock()
            )
        }

        var fullName = name
        try appendPostfixAccesses(to: &fullName)
        let arguments = try parseInvocationArgumentsIfPresent()
        return .macroApplication(
            name: fullName,
            arguments: arguments
        )
    }

    func macroArgumentClauseIsFollowedByBlock() -> Bool {
        guard peek() == .leftParen else {
            return false
        }

        var depth = 0
        var offset = 0
        repeat {
            switch peek(offset: offset) {
            case .leftParen:
                depth += 1
            case .rightParen:
                depth -= 1
            case .eof:
                return false
            default:
                break
            }
            offset += 1
        } while depth > 0

        return peek(offset: offset) == .leftBrace
    }

    mutating func parseStatementBlock() throws -> [Statement] {
        guard peek() == .leftBrace else {
            throw ParseError("Expected block body.")
        }
        try consume(.leftBrace)

        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement())
        }

        try consume(.rightBrace)
        return statements
    }
}
