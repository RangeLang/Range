import Foundation

extension Parser {
    func peek() -> Token {
        tokens[index].token
    }

    @discardableResult
    mutating func advance() -> Token {
        defer { index += 1 }
        return tokens[index].token
    }

    func peek(offset: Int) -> Token {
        let position = index + offset
        if position >= tokens.count {
            return .eof
        }
        return tokens[position].token
    }

    func previous() -> Token {
        let position = index - 1
        if position < 0 {
            return .eof
        }
        return tokens[position].token
    }

    func currentRange() -> RangeSourceRange? {
        guard index < tokens.count else {
            return tokens.last?.range
        }
        return tokens[index].range
    }

    mutating func consume(_ expected: Token) throws {
        guard peek() == expected else {
            throw ParseError("Expected \(expected), found \(peek()).", range: currentRange())
        }
        advance()
    }

    mutating func consumeKeyword(_ keyword: RangeSyntax.Keyword) throws {
        guard peek() == .keyword(keyword.rawValue) else {
            throw ParseError("Expected keyword \(keyword.rawValue).", range: currentRange())
        }
        advance()
    }

    mutating func consumeIdentifier() throws -> String {
        guard case .identifier(let value) = peek() else {
            throw ParseError("Expected identifier, found \(peek()).", range: currentRange())
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
            throw ParseError("Expected enum case name.", range: currentRange())
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
            throw ParseError("Expected callable name.", range: currentRange())
        }
    }

    mutating func consumeStringLiteral() throws -> String {
        guard case .stringLiteral(let value) = peek() else {
            throw ParseError("Expected string literal.", range: currentRange())
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

    mutating func parseTypedConstructionAnnotation() throws
        -> (type: TypeReference, initializer: Expression?)
    {
        var result = try parseTypeReferenceBaseNode()
        let constructionType = wrappedOptionalType(result) ?? result
        while peek() == .question {
            try consume(.question)
            result = .optional(result)
        }
        if peek() == .ellipsis {
            try consume(.ellipsis)
            result = .variadic(result)
        }
        let initializer: Expression?
        if peek() == .leftParen {
            initializer = normalizedTypedConstructionInitializer(
                .call(
                name: constructionType.displayName,
                arguments: try parseInvocationArgumentsIfPresent()
                ),
                for: result
            )
        } else {
            initializer = nil
        }
        return (result, initializer)
    }

    func shouldParseTypedConstructionAfterColon() -> Bool {
        switch peek() {
        case .identifier(let value), .keyword(let value):
            return value.first?.isUppercase == true
        case .leftBracket:
            return isBracketedTypeReferenceAfterColon()
        case .leftParen:
            return isFunctionTypeReferenceAfterColon()
        default:
            return false
        }
    }

    func isBracketedTypeReferenceAfterColon() -> Bool {
        var offset = 1
        switch peek(offset: offset) {
        case .identifier(let value) where value.first?.isUppercase == true,
            .keyword(let value) where value.first?.isUppercase == true:
            offset += 1
        case .markerAttribute, .macroAttribute:
            offset += 1
        default:
            return false
        }

        var genericDepth = 0
        while true {
            switch peek(offset: offset) {
            case .less:
                genericDepth += 1
            case .greater:
                genericDepth -= 1
            case .rightBracket where genericDepth == 0:
                return true
            case .colon where genericDepth == 0:
                return false
            case .eof:
                return false
            default:
                break
            }
            offset += 1
        }
    }

    func isFunctionTypeReferenceAfterColon() -> Bool {
        var depth = 0
        var offset = 0
        while true {
            switch peek(offset: offset) {
            case .leftParen:
                depth += 1
            case .rightParen:
                depth -= 1
                if depth == 0 {
                    return peek(offset: offset + 1) == .arrow
                }
            case .eof:
                return false
            default:
                break
            }
            offset += 1
        }
    }

    func normalizedTypedConstructionInitializer(
        _ expression: Expression,
        for type: TypeReference
    ) -> Expression {
        let normalizedTypeName = (wrappedOptionalType(type) ?? type).displayName
        guard case .call(let name, let arguments) = expression,
            name == normalizedTypeName,
            arguments.count == 1,
            arguments[0].label == nil
        else {
            return expression
        }

        switch (normalizedTypeName, arguments[0].value) {
        case ("Title", _), ("Version", _):
            return expression
        case ("Int", .integer),
            ("String", .string),
            ("String", .interpolatedString),
            ("Bool", .boolean),
            ("Float", .double),
            ("Double", .double):
            return arguments[0].value
        default:
            return arguments[0].value
        }
    }

    func wrappedOptionalType(_ type: TypeReference) -> TypeReference? {
        if case .optional(let wrapped) = type {
            return wrapped
        }
        return nil
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

        let baseName: String
        switch peek() {
        case .markerAttribute(let name):
            advance()
            baseName = "#\(name)"
        case .macroAttribute(let name, nil):
            advance()
            baseName = "@\(name)"
        case .macroAttribute(let name, _):
            throw ParseError("Macro handle @\(name) used as a type cannot include arguments.", range: currentRange())
        default:
            baseName = try consumeTypeName()
        }
        var result: TypeReference = .named(baseName)

        while peek() == .dot {
            try consume(.dot)
            result = .member(base: result, name: try consumeTypeName())
        }

        if peek() == .less {
            try consume(.less)
            var genericArguments: [TypeReference] = [try parseGenericArgumentReferenceNode()]
            while peek() == .comma {
                advance()
                genericArguments.append(try parseGenericArgumentReferenceNode())
            }
            try consume(.greater)
            if case .named("Optional") = result, genericArguments.count == 1 {
                return .optional(genericArguments[0])
            }
            result = .generic(base: result, arguments: genericArguments)
        }

        return result
    }

    mutating func parseGenericArgumentReferenceNode() throws -> TypeReference {
        switch peek() {
        case .integer(let value):
            advance()
            return .named(String(value))
        case .double(let value):
            advance()
            return .named(String(value))
        case .stringLiteral(let value):
            advance()
            return .named("\"\(value)\"")
        case .keyword("true"):
            advance()
            return .named("true")
        case .keyword("false"):
            advance()
            return .named("false")
        case .dot:
            try consume(.dot)
            return .named(".\(try consumeTypeName())")
        default:
            return try parseTypeReferenceNode()
        }
    }
}
