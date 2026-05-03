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
            throw ParseError("Expected identifier, found \(peek()).")
        }
        advance()
        return value
    }

    mutating func consumeEnumCaseName() throws -> String {
        switch peek() {
        case .identifier(let value):
            advance()
            return value
        case .keyword(let value):
            advance()
            return value
        default:
            throw ParseError("Expected enum case name.")
        }
    }

    mutating func consumeCallableName() throws -> String {
        switch peek() {
        case .identifier(let value):
            advance()
            return value
        case .keyword(let value):
            advance()
            return value
        case .plus:
            advance()
            return "+"
        case .minus:
            advance()
            return "-"
        case .asterisk:
            advance()
            return "*"
        case .slash:
            advance()
            return "/"
        case .percent:
            advance()
            return "%"
        case .equalEqual:
            advance()
            return "=="
        case .bangEqual:
            advance()
            return "!="
        case .less:
            advance()
            return "<"
        case .lessEqual:
            advance()
            return "<="
        case .greater:
            advance()
            return ">"
        case .greaterEqual:
            advance()
            return ">="
        case .questionQuestion:
            advance()
            return "??"
        default:
            throw ParseError("Expected callable name.")
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
        try parseTypeReferenceNode().displayName
    }

    mutating func parseNominalTypeReferenceNode(
        expectedDescription: String = "Type"
    ) throws -> TypeReference {
        let typeReference = try parseTypeReferenceNode()
        guard typeReference.isNominalReference else {
            throw ParseError(
                "\(expectedDescription) must be a nominal type reference, got \(typeReference.displayName)."
            )
        }
        return typeReference
    }

    mutating func parseTypeReferenceNode() throws -> TypeReference {
        var result = try parseTypeReferenceBaseNode()
        while peek() == .question {
            try consume(.question)
            result = .optional(result)
        }
        if peek() == .ellipsis {
            try consume(.ellipsis)
            result = .variadic(result)
        }
        return result
    }

    mutating func parseTypeReferenceBaseNode() throws -> TypeReference {
        if peek() == .leftParen {
            try consume(.leftParen)
            var parameterTypes: [TypeReference] = []

            if peek() != .rightParen {
                while true {
                    parameterTypes.append(try parseTypeReferenceNode())
                    guard peek() == .comma else { break }
                    advance()
                }
            }

            try consume(.rightParen)
            guard peek() == .arrow else {
                throw ParseError("Expected '->' in function type.")
            }
            try consume(.arrow)
            let returnType = try parseTypeReferenceNode()
            return .function(parameters: parameterTypes, returnType: returnType)
        }

        if peek() == .leftBracket {
            try consume(.leftBracket)
            let elementType = try parseTypeReferenceNode()
            try consume(.rightBracket)
            return .array(elementType)
        }

        var result: TypeReference = .named(try consumeTypeName())

        while peek() == .dot {
            try consume(.dot)
            result = .member(base: result, name: try consumeTypeName())
        }

        if peek() == .less {
            try consume(.less)
            var genericArguments: [TypeReference] = [try parseTypeReferenceNode()]
            while peek() == .comma {
                advance()
                genericArguments.append(try parseTypeReferenceNode())
            }
            try consume(.greater)
            result = .generic(base: result, arguments: genericArguments)
        }

        return result
    }
}
