import Foundation

extension Parser {
    func peek() -> Token {
        tokens[index]
    }

    @discardableResult
    mutating func advance() -> Token {
        defer { index += 1 }
        return tokens[index]
    }

    func peek(offset: Int) -> Token {
        let position = index + offset
        if position >= tokens.count {
            return .eof
        }
        return tokens[position]
    }

    func previous() -> Token {
        let position = index - 1
        if position < 0 {
            return .eof
        }
        return tokens[position]
    }

    mutating func consume(_ expected: Token) throws {
        guard peek() == expected else {
            throw ParseError("Expected \(expected), found \(peek()).")
        }
        advance()
    }

    mutating func consumeKeyword(_ keyword: NeatSyntax.Keyword) throws {
        guard peek() == .keyword(keyword.rawValue) else {
            throw ParseError("Expected keyword \(keyword.rawValue).")
        }
        advance()
    }

    mutating func consumeIdentifier() throws -> String {
        guard case .identifier(let value) = peek() else {
            throw ParseError("Expected identifier.")
        }
        advance()
        return value
    }

    mutating func consumeCallableName() throws -> String {
        switch peek() {
        case .identifier(let value):
            advance()
            return value
        case .keyword(let value):
            advance()
            return value
        default:
            throw ParseError("Expected component or node name.")
        }
    }

    mutating func consumeStringLiteral() throws -> String {
        guard case .stringLiteral(let value) = peek() else {
            throw ParseError("Expected string literal.")
        }
        advance()
        return value
    }

    mutating func consumeTypeName() throws -> String {
        switch peek() {
        case .identifier(let value):
            advance()
            return value
        case .keyword(let value):
            advance()
            return value
        default:
            throw ParseError("Expected type name.")
        }
    }

    mutating func consumeTypeReference() throws -> String {
        var result = try consumeTypeReferenceBase()
        while peek() == .question {
            try consume(.question)
            result += "?"
        }
        return result
    }

    mutating func consumeTypeReferenceBase() throws -> String {
        if peek() == .leftParen {
            try consume(.leftParen)
            var parameterTypes: [String] = []

            if peek() != .rightParen {
                while true {
                    parameterTypes.append(try consumeTypeReference())
                    guard peek() == .comma else { break }
                    advance()
                }
            }

            try consume(.rightParen)
            guard peek() == .arrow else {
                throw ParseError("Expected '->' in function type.")
            }
            try consume(.arrow)
            let returnType = try consumeTypeReference()
            let renderedParameters = parameterTypes.joined(separator: ", ")
            return "(\(renderedParameters)) -> \(returnType)"
        }

        if peek() == .leftBracket {
            try consume(.leftBracket)
            let elementType = try consumeTypeReference()
            try consume(.rightBracket)
            return "[\(elementType)]"
        }

        var parts: [String] = [try consumeTypeName()]

        while peek() == .dot {
            try consume(.dot)
            parts.append(try consumeTypeName())
        }

        var result = parts.joined(separator: ".")
        if peek() == .less {
            try consume(.less)
            var genericArguments: [String] = [try consumeTypeReference()]
            while peek() == .comma {
                advance()
                genericArguments.append(try consumeTypeReference())
            }
            try consume(.greater)
            result += "<\(genericArguments.joined(separator: ", "))>"
        }

        return result
    }
}
