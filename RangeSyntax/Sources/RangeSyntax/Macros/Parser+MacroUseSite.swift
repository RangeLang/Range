import Foundation

extension Parser {
    func isMacroApplicationStart() -> Bool {
        if case .hashDirective = peek() {
            return true
        }
        if case .atAttribute(let name, _) = peek(), isMacroApplicationAttribute(name) {
            return true
        }
        return false
    }

    func macroApplicationLookaheadLength() -> Int {
        var offset = 0
        while true {
            guard macroApplicationName(at: offset) != nil else {
                break
            }

            offset += 1
            if peek(offset: offset) == .less {
                var depth = 1
                offset += 1
                while depth > 0 {
                    switch peek(offset: offset) {
                    case .less:
                        depth += 1
                    case .greater:
                        depth -= 1
                    case .eof:
                        return offset
                    default:
                        break
                    }
                    offset += 1
                }
            }

            if peek(offset: offset) == .leftParen {
                var depth = 1
                offset += 1
                while depth > 0 {
                    switch peek(offset: offset) {
                    case .leftParen:
                        depth += 1
                    case .rightParen:
                        depth -= 1
                    case .eof:
                        return offset
                    default:
                        break
                    }
                    offset += 1
                }
            }

            if peek(offset: offset) == .leftBrace,
                peek(offset: offset + 1).isForeignBody,
                peek(offset: offset + 2) == .rightBrace
            {
                offset += 3
            }

            continue
        }
        return offset
    }

    mutating func parseMacroApplicationsIfPresent() throws -> [MacroApplication] {
        var macros: [MacroApplication] = []

        while true {
            guard let name = macroApplicationName(at: 0) else {
                break
            }

            advance()
            let genericArguments = try parseMacroGenericArgumentsIfPresent()
            let argumentClause = try parseMacroArgumentClauseIfPresent()
            let rawBody = try parseMacroRawBodyIfPresent()
            macros.append(
                MacroApplication(
                    name: name,
                    genericArguments: genericArguments,
                    argumentClause: argumentClause,
                    rawBodyLanguage: rawBody?.language,
                    rawBody: rawBody?.text
                )
            )
        }

        return macros
    }

    func macroApplicationName(at offset: Int) -> String? {
        switch peek(offset: offset) {
        case .hashDirective(let name):
            return name
        case .atAttribute(let name, _) where isMacroApplicationAttribute(name, offset: offset):
            return name
        default:
            return nil
        }
    }

    func isMacroApplicationAttribute(_ name: String, offset: Int = 0) -> Bool {
        if macroDeclarationsByName[name] != nil {
            return true
        }
        guard !RangeSyntax.attributeIdentifiers.contains(name) else {
            return false
        }
        switch peek(offset: offset + 1) {
        case .less, .leftParen, .identifier:
            return true
        default:
            return false
        }
    }

    mutating func parseMacroGenericArgumentsIfPresent() throws -> [TypeReference] {
        guard peek() == .less else {
            return []
        }

        try consume(.less)
        var arguments: [TypeReference] = [try parseTypeReferenceNode()]
        while peek() == .comma {
            advance()
            arguments.append(try parseTypeReferenceNode())
        }
        try consume(.greater)
        return arguments
    }

    mutating func parseMacroArgumentClauseIfPresent() throws -> String? {
        guard peek() == .leftParen else {
            return nil
        }

        try consume(.leftParen)
        var depth = 1
        var parts: [String] = []

        while depth > 0 {
            let token = advance()
            switch token {
            case .leftParen:
                depth += 1
                parts.append(renderMacroToken(token))
            case .rightParen:
                depth -= 1
                if depth > 0 {
                    parts.append(renderMacroToken(token))
                }
            case .eof:
                throw ParseError("Unterminated macro argument clause.")
            default:
                parts.append(renderMacroToken(token))
            }
        }

        return parts.joined(separator: " ")
    }

    mutating func parseMacroRawBodyIfPresent() throws -> (language: String, text: String)? {
        guard peek() == .leftBrace else {
            return nil
        }
        guard case .foreignBody(let language, let text) = peek(offset: 1) else {
            return nil
        }

        try consume(.leftBrace)
        advance()
        try consume(.rightBrace)
        return (language, text)
    }

    func renderMacroToken(_ token: Token) -> String {
        switch token {
        case .hash:
            return "#"
        case .identifier(let value):
            return value
        case .hashDirective(let value):
            return "#\(value)"
        case .foreignBody(_, let value):
            return value
        case .stringLiteral(let value):
            return "\"\(value)\""
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .keyword(let value):
            return value
        case .atAttribute(let name, let argument):
            if let argument {
                return "@\(name)(\(argument))"
            }
            return "@\(name)"
        case .leftBrace:
            return "{"
        case .rightBrace:
            return "}"
        case .leftParen:
            return "("
        case .rightParen:
            return ")"
        case .leftBracket:
            return "["
        case .rightBracket:
            return "]"
        case .asterisk:
            return "*"
        case .dot:
            return "."
        case .ellipsis:
            return "..."
        case .colon:
            return ":"
        case .arrow:
            return "->"
        case .bang:
            return "!"
        case .equal:
            return "="
        case .equalEqual:
            return "=="
        case .bangEqual:
            return "!="
        case .minus:
            return "-"
        case .less:
            return "<"
        case .lessEqual:
            return "<="
        case .greater:
            return ">"
        case .greaterEqual:
            return ">="
        case .plus:
            return "+"
        case .plusEqual:
            return "+="
        case .slash:
            return "/"
        case .ampersand:
            return "&"
        case .andAnd:
            return "&&"
        case .pipe:
            return "|"
        case .orOr:
            return "||"
        case .question:
            return "?"
        case .questionQuestion:
            return "??"
        case .dollar:
            return "$"
        case .percent:
            return "%"
        case .comma:
            return ","
        case .eof:
            return ""
        }
    }
}
