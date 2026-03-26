import Foundation

extension Parser {
    func isMacroApplicationStart() -> Bool {
        if case .hashDirective = peek() {
            return true
        }
        return false
    }

    func macroApplicationLookaheadLength() -> Int {
        var offset = 0
        while case .hashDirective = peek(offset: offset) {
            offset += 1
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
        }
        return offset
    }

    mutating func parseMacroApplicationsIfPresent() throws -> [MacroApplication] {
        var macros: [MacroApplication] = []

        while case .hashDirective(let name) = peek() {
            advance()
            let argumentClause = try parseMacroArgumentClauseIfPresent()
            macros.append(MacroApplication(name: name, argumentClause: argumentClause))
        }

        return macros
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

    func renderMacroToken(_ token: Token) -> String {
        switch token {
        case .identifier(let value):
            return value
        case .hashDirective(let value):
            return "#\(value)"
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
        case .andAnd:
            return "&&"
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
