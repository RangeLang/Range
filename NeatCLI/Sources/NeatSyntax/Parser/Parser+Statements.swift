import Foundation

extension Parser {
    mutating func parseStatement(
        localBindings: inout [String: LocalBindingKind]
    ) throws -> Statement {
        if case .keyword(NeatSyntax.Keyword.switchStatement.rawValue) = peek() {
            return try parseSwitchStatement(localBindings: &localBindings)
        }

        if case .keyword(NeatSyntax.Keyword.constant.rawValue) = peek() {
            advance()
            return try parseLocalDeclaration(kind: .constant, localBindings: &localBindings)
        }
        if case .keyword(NeatSyntax.Keyword.variable.rawValue) = peek() {
            advance()
            return try parseLocalDeclaration(kind: .mutable, localBindings: &localBindings)
        }

        let name = try consumeIdentifier()

        if name == "print" {
            try consume(.leftParen)
            let message = try consumeStringLiteral()
            try consume(.rightParen)
            return .debugPrint(parseInterpolatedString(message))
        }

        let target = try resolveAssignmentTarget(name: name, localBindings: localBindings)

        switch peek() {
        case .equal:
            advance()
            return .assignment(target: target, expression: try parseExpression())
        case .plusEqual:
            advance()
            return .compoundAssignment(
                target: target,
                operatorSymbol: .plusEquals,
                expression: try parseExpression()
            )
        default:
            throw ParseError("Expected assignment operator in action block.")
        }
    }

    mutating func parseLocalDeclaration(
        kind: LocalBindingKind,
        localBindings: inout [String: LocalBindingKind]
    ) throws -> Statement {
        let name = try consumeIdentifier()
        if localBindings[name] != nil {
            throw ParseError("'\(name)' is already declared in this scope.")
        }
        if currentStateNames.contains(name) {
            throw ParseError("Local binding '\(name)' conflicts with @State '\(name)'.")
        }

        try consume(.equal)
        let expression = try parseExpression()
        localBindings[name] = kind
        return .declaration(kind: kind, name: name, expression: expression)
    }

    func resolveAssignmentTarget(
        name: String,
        localBindings: [String: LocalBindingKind]
    ) throws -> AssignmentTarget {
        if let localKind = localBindings[name] {
            if case .constant = localKind {
                throw ParseError("Cannot assign to let constant '\(name)'.")
            }
            return .local(name)
        }

        if currentStateNames.contains(name) {
            return .state(name)
        }

        throw ParseError("Unknown mutable symbol '\(name)'. Declare it with var/let or @State.")
    }

    mutating func parseSwitchStatement(
        localBindings: inout [String: LocalBindingKind]
    ) throws -> Statement {
        try consumeKeyword(.switchStatement)
        let subject = try parseExpression()
        try consume(.leftBrace)

        var cases: [SwitchCase] = []
        var defaultBody: [Statement]?

        while peek() != .rightBrace {
            if case .keyword(NeatSyntax.Keyword.caseBranch.rawValue) = peek() {
                try consumeKeyword(.caseBranch)
                let value = try parseExpression()
                let body = try parseSwitchBodyStatements(baseLocalBindings: localBindings)
                cases.append(SwitchCase(value: value, body: body))
                continue
            }

            if case .keyword(NeatSyntax.Keyword.defaultBranch.rawValue) = peek() {
                try consumeKeyword(.defaultBranch)
                if defaultBody != nil {
                    throw ParseError("Switch can only contain one default block.")
                }
                defaultBody = try parseSwitchBodyStatements(baseLocalBindings: localBindings)
                continue
            }

            throw ParseError("Expected case or default inside switch block.")
        }

        try consume(.rightBrace)
        return .switchStatement(expression: subject, cases: cases, defaultBody: defaultBody)
    }

    mutating func parseSwitchBodyStatements(baseLocalBindings: [String: LocalBindingKind])
        throws -> [Statement]
    {
        if peek() == .colon {
            try consume(.colon)
        }

        guard peek() == .leftBrace else {
            throw ParseError("Switch case/default requires a block body.")
        }
        try consume(.leftBrace)

        var localBindings = baseLocalBindings
        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        try consume(.rightBrace)
        return statements
    }

    func isStatementStart() -> Bool {
        if peek() == .keyword(NeatSyntax.Keyword.switchStatement.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.constant.rawValue)
            || peek() == .keyword(NeatSyntax.Keyword.variable.rawValue)
        {
            return true
        }

        guard case .identifier(let name) = peek() else { return false }
        if name == "print" && peek(offset: 1) == .leftParen {
            return true
        }
        let next = peek(offset: 1)
        return next == .equal || next == .plusEqual
    }
}
