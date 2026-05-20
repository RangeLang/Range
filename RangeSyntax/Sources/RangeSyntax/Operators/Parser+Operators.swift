import Foundation

extension Parser {
    func isPrecedenceGroupDeclarationStart() -> Bool {
        peek() == .keyword(RangeSyntax.Keyword.precedencegroup.rawValue)
    }

    func isOperatorDeclarationStart() -> Bool {
        switch peek() {
        case .keyword(RangeSyntax.Keyword.infix.rawValue),
            .keyword(RangeSyntax.Keyword.prefix.rawValue),
            .keyword(RangeSyntax.Keyword.postfix.rawValue):
            return peek(offset: 1) == .keyword(RangeSyntax.Keyword.operatorKeyword.rawValue)
        default:
            return false
        }
    }

    mutating func parsePrecedenceGroupDeclaration(requiresEOF: Bool = true) throws
        -> PrecedenceGroupDeclaration
    {
        try consumeKeyword(.precedencegroup)
        let name = try consumeTypeName()
        try consume(.leftBrace)

        var associativity: OperatorAssociativity?
        var higherThan: [String] = []
        var lowerThan: [String] = []
        var assignment: Bool?

        while peek() != .rightBrace {
            let clauseName = try consumeTypeName()
            try consume(.colon)

            switch clauseName {
            case "associativity":
                guard associativity == nil else {
                    throw ParseError(
                        "Duplicate associativity clause in precedencegroup \(name).")
                }
                let rawValue = try consumeTypeName()
                guard let parsed = OperatorAssociativity(rawValue: rawValue) else {
                    throw ParseError(
                        "Invalid associativity '\(rawValue)' in precedencegroup \(name).")
                }
                associativity = parsed

            case "higherThan":
                guard higherThan.isEmpty else {
                    throw ParseError(
                        "Duplicate higherThan clause in precedencegroup \(name).")
                }
                higherThan = try parsePrecedenceGroupNameList()

            case "lowerThan":
                guard lowerThan.isEmpty else {
                    throw ParseError(
                        "Duplicate lowerThan clause in precedencegroup \(name).")
                }
                lowerThan = try parsePrecedenceGroupNameList()

            case "assignment":
                guard assignment == nil else {
                    throw ParseError(
                        "Duplicate assignment clause in precedencegroup \(name).")
                }
                assignment = try parseBooleanClauseValue(
                    expecting: "assignment clause in precedencegroup \(name)")

            default:
                throw ParseError(
                    "Unknown precedencegroup clause '\(clauseName)' in \(name).")
            }
        }

        try consume(.rightBrace)
        if requiresEOF {
            try consume(.eof)
        }

        return PrecedenceGroupDeclaration(
            name: name,
            associativity: associativity,
            higherThan: higherThan,
            lowerThan: lowerThan,
            assignment: assignment
        )
    }

    mutating func parseOperatorDeclaration(requiresEOF: Bool = true) throws -> OperatorDeclaration {
        let fixity: OperatorFixity
        switch peek() {
        case .keyword(RangeSyntax.Keyword.prefix.rawValue):
            fixity = .prefix
        case .keyword(RangeSyntax.Keyword.infix.rawValue):
            fixity = .infix
        case .keyword(RangeSyntax.Keyword.postfix.rawValue):
            fixity = .postfix
        default:
            throw ParseError("Expected operator declaration.")
        }
        advance()

        try consumeKeyword(.operatorKeyword)
        let symbol = try consumeOperatorSymbol()
        let precedenceGroup: String?

        if peek() == .colon {
            try consume(.colon)
            precedenceGroup = try consumeTypeName()
        } else {
            precedenceGroup = nil
        }

        if requiresEOF {
            try consume(.eof)
        }

        return OperatorDeclaration(
            fixity: fixity,
            symbol: symbol,
            precedenceGroup: precedenceGroup
        )
    }

    mutating func parsePrecedenceGroupNameList() throws -> [String] {
        var names: [String] = [try consumeTypeName()]
        while peek() == .comma {
            advance()
            names.append(try consumeTypeName())
        }
        return names
    }

    mutating func parseBooleanClauseValue(expecting context: String) throws -> Bool {
        let rawValue = try consumeTypeName()
        switch rawValue {
        case "true":
            return true
        case "false":
            return false
        default:
            throw ParseError("Expected Bool value in \(context).")
        }
    }

    mutating func consumeOperatorSymbol() throws -> String {
        switch peek() {
        case .minus:
            advance()
            return "-"
        case .plus:
            advance()
            return "+"
        case .asterisk:
            advance()
            return "*"
        case .slash:
            advance()
            return "/"
        case .percent:
            advance()
            return "%"
        case .plusEqual:
            advance()
            return "+="
        case .colonEqual:
            advance()
            return ":="
        case .bang:
            advance()
            return "!"
        case .equal:
            advance()
            return "="
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
        case .andAnd:
            advance()
            return "&&"
        case .orOr:
            advance()
            return "||"
        case .ellipsis:
            advance()
            return "..."
        default:
            throw ParseError("Expected operator symbol.")
        }
    }
}
