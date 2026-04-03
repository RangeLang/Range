import Foundation

extension Parser {
    mutating func parseStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        if isMacroApplicationStart() {
            return try parseFreestandingMacroStatement(localBindings: &localBindings)
        }

        if isEnvironmentProvisionStart() {
            return .environmentProvision(try parseEnvironmentProvision())
        }

        if case .keyword(NeatSyntax.Keyword.ifStatement.rawValue) = peek() {
            return try parseIfStatement(localBindings: &localBindings)
        }

        if case .keyword(NeatSyntax.Keyword.whileLoop.rawValue) = peek() {
            return try parseWhileStatement(localBindings: &localBindings)
        }

        if case .keyword(NeatSyntax.Keyword.forLoop.rawValue) = peek() {
            return try parseForStatement(localBindings: &localBindings)
        }

        if case .keyword(NeatSyntax.Keyword.switchStatement.rawValue) = peek() {
            return try parseSwitchStatement(localBindings: &localBindings)
        }

        if case .keyword(NeatSyntax.Keyword.value.rawValue) = peek() {
            advance()
            return try parseLocalDeclaration(kind: .constant, localBindings: &localBindings)
        }
        if case .keyword(NeatSyntax.Keyword.state.rawValue) = peek() {
            advance()
            return try parseLocalDeclaration(kind: .mutable, localBindings: &localBindings)
        }
        if case .keyword(NeatSyntax.Keyword.derived.rawValue) = peek() {
            advance()
            return try parseLocalDerived(localBindings: &localBindings)
        }

        if case .keyword(NeatSyntax.Keyword.returnStatement.rawValue) = peek() {
            advance()
            if peek() == .rightBrace {
                return .return(nil)
            }
            return .return(try parseExpression())
        }

        if case .keyword(NeatSyntax.Keyword.breakStatement.rawValue) = peek() {
            advance()
            return .break
        }

        if case .keyword(NeatSyntax.Keyword.continueStatement.rawValue) = peek() {
            advance()
            return .continue
        }

        if isExpressionStatementStart() && !isAssignmentStatementStart() {
            return .expression(try parseExpression())
        }

        let target = try parseAssignmentTarget(localBindings: localBindings)

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

    mutating func parseFreestandingMacroStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        guard case .hashDirective(let name) = peek() else {
            throw ParseError("Expected freestanding macro application.")
        }
        advance()
        let argumentClause = try parseMacroArgumentClauseIfPresent()
        let body = try parseStatementBlock(baseLocalBindings: localBindings)
        return .freestandingMacro(name: name, argumentClause: argumentClause, body: body)
    }

    func isStandaloneCallExpressionStart() -> Bool {
        guard case .identifier = peek() else { return false }
        var offset = 1
        while peek(offset: offset) == .dot {
            guard case .identifier = peek(offset: offset + 1) else {
                return false
            }
            offset += 2
        }

        return peek(offset: offset) == .leftParen
    }

    func isAssignmentStatementStart() -> Bool {
        guard case .identifier = peek() else { return false }
        var offset = 1
        while peek(offset: offset) == .dot {
            guard case .identifier = peek(offset: offset + 1) else {
                return false
            }
            offset += 2
        }
        let next = peek(offset: offset)
        return next == .equal || next == .plusEqual
    }

    func isExpressionStatementStart() -> Bool {
        switch peek() {
        case .identifier, .integer, .double, .stringLiteral, .leftBracket, .leftParen, .dollar,
            .dot, .bang:
            return true
        default:
            return false
        }
    }

    mutating func parseLocalDeclaration(
        kind: LocalBindingKind,
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        let name = try consumeIdentifier()
        if localBindings[name] != nil {
            throw ParseError("'\(name)' is already declared in this scope.")
        }
        if currentStateNames.contains(name) {
            throw ParseError("Local binding '\(name)' conflicts with state '\(name)'.")
        }
        if currentEnvironmentNames.contains(name) {
            throw ParseError("Local binding '\(name)' conflicts with environment '\(name)'.")
        }

        let explicitType: TypeReference?
        if peek() == .colon {
            try consume(.colon)
            explicitType = try parseTypeReferenceNode()
        } else {
            explicitType = nil
        }

        try consume(.equal)
        let expression = try parseExpression()
        let resolvedType = try inferInitializedBindingType(
            name: name,
            explicitType: explicitType,
            expression: expression,
            accessibleTypes: accessibleLocalTypes(localBindings),
            bindingKindDescription: kind == .constant ? "value" : "state"
        )
        let declaration = LocalBindingDeclaration(
            kind: kind,
            name: name,
            hasExplicitTypeAnnotation: explicitType != nil,
            type: explicitType ?? resolvedType,
            expression: expression
        )
        localBindings[name] = LocalBindingSymbol(kind: kind, type: declaration.type)
        return .localBinding(declaration)
    }

    mutating func parseLocalDerived(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        let name = try consumeIdentifier()
        if localBindings[name] != nil {
            throw ParseError("'\(name)' is already declared in this scope.")
        }
        if currentStateNames.contains(name) {
            throw ParseError("Local derived '\(name)' conflicts with state '\(name)'.")
        }
        if currentEnvironmentNames.contains(name) {
            throw ParseError("Local derived '\(name)' conflicts with environment '\(name)'.")
        }

        try consume(.colon)
        let typeName = try consumeTypeReference()
        let body = try parseStatementBlock(baseLocalBindings: localBindings)
        localBindings[name] = LocalBindingSymbol(kind: .constant, type: .named(typeName))
        return .derived(name: name, typeName: typeName, body: body)
    }

    mutating func parseAssignmentTarget(
        localBindings: [String: LocalBindingSymbol]
    ) throws -> AssignmentTarget {
        let name = try consumeIdentifier()
        var target: AssignmentTarget
        if currentSelfAvailable, name == "self" {
            guard peek() == .dot else {
                throw ParseError("Cannot assign to self directly.")
            }
            target = .local(name)
        } else {
            target = try resolveAssignmentTarget(name: name, localBindings: localBindings)
        }
        while peek() == .dot {
            try consume(.dot)
            let memberName = try consumeIdentifier()
            target = .member(base: target, name: memberName)
        }
        return target
    }

    func resolveAssignmentTarget(
        name: String,
        localBindings: [String: LocalBindingSymbol]
    ) throws -> AssignmentTarget {
        if let localBinding = localBindings[name] {
            if case .constant = localBinding.kind {
                throw ParseError("Cannot assign to immutable value '\(name)'.")
            }
            return .local(name)
        }

        if currentMutableStateNames.contains(name) {
            return .state(name)
        }

        if currentBindingNames.contains(name) {
            return .binding(name)
        }

        if currentMutableEnvironmentNames.contains(name) {
            return .environment(name)
        }

        if currentEnvironmentNames.contains(name) {
            throw ParseError("Cannot assign to environment '\(name)'.")
        }

        if currentStateNames.contains(name) {
            throw ParseError("Cannot assign to derived state '\(name)'.")
        }

        throw ParseError("Unknown mutable symbol '\(name)'. Declare it with value or state.")
    }

    mutating func parseSwitchStatement(
        localBindings: inout [String: LocalBindingSymbol]
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

    mutating func parseIfStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        var branches: [StatementConditionalBranch] = []

        try consumeKeyword(.ifStatement)
        let condition = try parseExpression()
        let body = try parseStatementBlock(baseLocalBindings: localBindings)
        branches.append(StatementConditionalBranch(condition: condition, body: body))

        while peek() == .keyword(NeatSyntax.Keyword.elseBranch.rawValue) {
            try consumeKeyword(.elseBranch)

            if peek() == .keyword(NeatSyntax.Keyword.ifStatement.rawValue) {
                try consumeKeyword(.ifStatement)
                let elseIfCondition = try parseExpression()
                let elseIfBody = try parseStatementBlock(baseLocalBindings: localBindings)
                branches.append(
                    StatementConditionalBranch(condition: elseIfCondition, body: elseIfBody))
                continue
            }

            let elseBody = try parseStatementBlock(baseLocalBindings: localBindings)
            branches.append(StatementConditionalBranch(condition: nil, body: elseBody))
            break
        }

        return .conditional(branches)
    }

    mutating func parseWhileStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        try consumeKeyword(.whileLoop)
        let condition = try parseExpression()
        let body = try parseStatementBlock(baseLocalBindings: localBindings)
        return .whileLoop(condition: condition, body: body)
    }

    mutating func parseForStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        try consumeKeyword(.forLoop)
        let name = try consumeIdentifier()
        guard localBindings[name] == nil else {
            throw ParseError("'\(name)' is already declared in this scope.")
        }
        guard !currentStateNames.contains(name) else {
            throw ParseError("Loop binding '\(name)' conflicts with state '\(name)'.")
        }
        guard !currentEnvironmentNames.contains(name) else {
            throw ParseError("Loop binding '\(name)' conflicts with environment '\(name)'.")
        }

        try consumeKeyword(.inKeyword)
        let sequence = try parseExpression()
        try consume(.leftBrace)

        var loopBindings = localBindings
        loopBindings[name] = LocalBindingSymbol(kind: .constant, type: .named("Never"))
        var body: [Statement] = []
        while peek() != .rightBrace {
            body.append(try parseStatement(localBindings: &loopBindings))
        }

        try consume(.rightBrace)
        return .forEach(name: name, sequence: sequence, body: body)
    }

    mutating func parseSwitchBodyStatements(baseLocalBindings: [String: LocalBindingSymbol])
        throws -> [Statement]
    {
        if peek() == .colon {
            try consume(.colon)
        }

        return try parseStatementBlock(baseLocalBindings: baseLocalBindings)
    }

    mutating func parseStatementBlock(baseLocalBindings: [String: LocalBindingSymbol]) throws
        -> [Statement]
    {
        guard peek() == .leftBrace else {
            throw ParseError("Expected block body.")
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
        if peek() == .keyword(NeatSyntax.Keyword.ifStatement.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.whileLoop.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.forLoop.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.switchStatement.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.returnStatement.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.breakStatement.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.continueStatement.rawValue) {
            return true
        }
        if peek() == .keyword(NeatSyntax.Keyword.value.rawValue)
            || peek() == .keyword(NeatSyntax.Keyword.state.rawValue)
            || peek() == .keyword(NeatSyntax.Keyword.derived.rawValue)
        {
            return true
        }

        return isExpressionStatementStart()
    }

    func accessibleLocalTypes(_ localBindings: [String: LocalBindingSymbol]) -> [String:
        TypeReference]
    {
        let localTypes = Dictionary(
            uniqueKeysWithValues: localBindings.map { ($0.key, $0.value.type) }
        )
        return accessibleContextTypes().merging(localTypes) { current, _ in current }
    }
}
