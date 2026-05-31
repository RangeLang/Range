import Foundation

extension Parser {
    mutating func parseStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        let previousClosureBaseLocalBindings = currentClosureBaseLocalBindings
        currentClosureBaseLocalBindings = localBindings
        defer { currentClosureBaseLocalBindings = previousClosureBaseLocalBindings }

        if let targetPath = targetExpandStatementPath() {
            guard currentMacroBodyDepth > 0 else {
                throw ParseError("expand is only valid inside macro bodies.")
            }
            return try parseTargetExpandStatement(targetPath: targetPath)
        }

        if isRequireStatementStart() {
            return try parseRequireStatement()
        }

        if isMacroApplicationStart() {
            return .expression(try parseExpression())
        }

        if isLocalBackgroundCallableStart() {
            return try parseLocalBackgroundCallableDeclaration(localBindings: &localBindings)
        }

        if isBackgroundStatementStart() {
            return try parseBackgroundStatement(localBindings: &localBindings)
        }

        if isDeferStatementStart() {
            return try parseDeferStatement(localBindings: &localBindings)
        }

        if case .keyword(RangeSyntax.Keyword.ifStatement.rawValue) = peek() {
            return try parseIfStatement(localBindings: &localBindings)
        }

        if case .keyword(RangeSyntax.Keyword.whileLoop.rawValue) = peek() {
            return try parseWhileStatement(localBindings: &localBindings)
        }

        if case .keyword(RangeSyntax.Keyword.forLoop.rawValue) = peek() {
            return try parseForStatement(localBindings: &localBindings)
        }

        if case .keyword(RangeSyntax.Keyword.switchStatement.rawValue) = peek() {
            return try parseSwitchStatement(localBindings: &localBindings)
        }

        if case .keyword(RangeSyntax.Keyword.let.rawValue) = peek() {
            advance()
            return try parseLocalDeclaration(kind: .constant, localBindings: &localBindings)
        }
        if case .keyword(RangeSyntax.Keyword.state.rawValue) = peek() {
            advance()
            return try parseLocalDeclaration(kind: .mutable, localBindings: &localBindings)
        }
        if case .keyword(RangeSyntax.Keyword.derived.rawValue) = peek() {
            advance()
            return try parseLocalDerived(localBindings: &localBindings)
        }

        if case .keyword(RangeSyntax.Keyword.returnStatement.rawValue) = peek() {
            advance()
            if peek() == .rightBrace {
                return .return(nil)
            }
            return .return(try parseExpression())
        }

        if case .keyword(RangeSyntax.Keyword.breakStatement.rawValue) = peek() {
            advance()
            return .break
        }

        if case .keyword(RangeSyntax.Keyword.continueStatement.rawValue) = peek() {
            advance()
            return .continue
        }

        if case .keyword("set") = peek() {
            advance()
            let target = try parseAssignmentTarget(localBindings: localBindings)
            return .assignment(target: target, expression: try parseExpression())
        }

        if isExpressionStatementStart() && !isAssignmentStatementStart() {
            return .expression(try parseExpression())
        }

        let target = try parseAssignmentTarget(localBindings: localBindings)

        switch peek() {
        case .plusEqual:
            advance()
            return .compoundAssignment(
                target: target,
                operatorSymbol: .plusEquals,
                expression: try parseExpression()
            )
        default:
            throw ParseError("Expected assignment operator (`+=`) or `set` statement in action block.")
        }
    }

    func isRequireStatementStart() -> Bool {
        guard case .markerAttribute(let name) = peek(), name == "Require" else {
            return false
        }
        return peek(offset: 1) == .leftParen
    }

    mutating func parseRequireStatement() throws -> Statement {
        guard case .markerAttribute(let name) = peek(), name == "Require" else {
            throw ParseError("Expected #Require statement.")
        }
        _ = name
        advance()
        try consume(.leftParen)
        let target = try parseExpression(terminatingAt: [.rightParen])
        try consume(.rightParen)
        try consume(.leftBrace)
        var members: [RequirementMember] = []
        while peek() != .rightBrace {
            members.append(try parseRequirementMember())
        }
        try consume(.rightBrace)
        return .require(target: target, members: members)
    }

    mutating func parseRequirementMember() throws -> RequirementMember {
        switch peek() {
        case .keyword(RangeSyntax.Keyword.let.rawValue):
            advance()
            return try parseRequiredProperty(kind: .let)
        case .keyword(RangeSyntax.Keyword.state.rawValue):
            advance()
            return try parseRequiredProperty(kind: .state)
        case .keyword(RangeSyntax.Keyword.binding.rawValue):
            advance()
            return try parseRequiredProperty(kind: .binding)
        case .keyword(RangeSyntax.Keyword.derived.rawValue):
            advance()
            return try parseRequiredProperty(kind: .derived)
        case .keyword(RangeSyntax.Keyword.function.rawValue):
            advance()
            let name = try consumeCallableName()
            let parameters = peek() == .leftParen ? try parseFunctionParameters() : []
            let returnType: TypeReference?
            if peek() == .arrow || peek() == .colon {
                advance()
                returnType = try parseTypeReferenceNode()
            } else {
                returnType = nil
            }
            return .function(name: name, parameters: parameters, returnType: returnType)
        default:
            throw ParseError("#Require blocks can require let, state, binding, derived, or function members.")
        }
    }

    mutating func parseRequiredProperty(kind: RequirementPropertyKind) throws -> RequirementMember {
        let name = try consumeIdentifier()
        try consume(.colon)
        let type = try parseTypeReferenceNode()
        return .property(kind: kind, name: name, type: type)
    }

    func targetExpandStatementPath() -> String? {
        guard let first = tokenIdentifierOrKeyword(peek()) else {
            return nil
        }

        var components = [first]
        var offset = 1
        while peek(offset: offset) == .dot {
            guard let component = tokenIdentifierOrKeyword(peek(offset: offset + 1)) else {
                return nil
            }
            components.append(component)
            offset += 2
        }

        guard components.count > 1,
            components.last == "expand",
            peek(offset: offset) == .leftBrace
        else {
            return nil
        }

        return components.dropLast().joined(separator: ".")
    }

    private func tokenIdentifierOrKeyword(_ token: Token) -> String? {
        switch token {
        case .identifier(let value), .keyword(let value):
            return value
        default:
            return nil
        }
    }

    func isBackgroundStatementStart() -> Bool {
        guard case .macroAttribute(let name, _) = peek(), name == "background" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    func isDeferStatementStart() -> Bool {
        guard case .macroAttribute(let name, _) = peek(), name == "defer" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    func isLocalBackgroundCallableStart() -> Bool {
        guard case .macroAttribute(let name, _) = peek(), name == "background" else {
            return false
        }

        guard tokenCanStartLocalBackgroundCallableName(peek(offset: 1)) else {
            return false
        }

        let next = peek(offset: 2)
        return next == .leftParen || next == .less
    }

    func tokenCanStartLocalBackgroundCallableName(_ token: Token) -> Bool {
        switch token {
        case .identifier, .keyword:
            return true
        default:
            return false
        }
    }

    mutating func parseLocalBackgroundCallableDeclaration(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        _ = localBindings

        guard case .macroAttribute(let name, _) = peek(), name == "background" else {
            throw ParseError("Expected @background callable declaration.")
        }

        advance()
        let callableName = try consumeCallableName()

        if peek() == .less {
            try skipGenericParameterClauseIfPresent()
        }

        if peek() == .leftParen {
            _ = try parseFunctionParameters()
        }

        if peek() == .colon || peek() == .arrow {
            advance()
            _ = try parseTypeReferenceNode()
        }

        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }

        throw ParseError(
            "Named @background callables are not supported: \(callableName)."
        )
    }

    mutating func parseBackgroundStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        guard case .macroAttribute(let name, _) = peek(), name == "background" else {
            throw ParseError("Expected @background block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: localBindings)
        return .background(Background(body: body))
    }

    mutating func parseDeferStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        guard case .macroAttribute(let name, _) = peek(), name == "defer" else {
            throw ParseError("Expected @defer block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: localBindings)
        return .deferBlock(DeferredBlock(body: body))
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
        return next == .plusEqual
    }

    func isExpressionStatementStart() -> Bool {
        switch peek() {
        case .identifier, .integer, .double, .stringLiteral, .markerAttribute, .leftBracket,
            .leftParen, .dollar, .dot, .bang:
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

        let explicitType: TypeReference?
        let typedInitializer: Expression?
        if peek() == .colon {
            try consume(.colon)
            if shouldParseTypedConstructionAfterColon() {
                let annotation = try parseTypedConstructionAnnotation()
                explicitType = annotation.type
                typedInitializer = annotation.initializer
                if canStartInlineExpression() {
                    throw ParseError(
                        "\(kind == .constant ? "let" : "state") '\(name)' expects one initializer after ':'. Use typed construction, for example `\(kind == .constant ? "let" : "state") \(name): \(annotation.type.displayName)(value)`."
                    )
                }
            } else {
                explicitType = nil
                typedInitializer = try parseExpression()
            }
        } else {
            explicitType = nil
            typedInitializer = nil
        }

        let expression: Expression
        if peek() == .equal {
            throw ParseError(
                "\(kind == .constant ? "let" : "state") '\(name)' expects declaration initialization after ':'. Use typed construction, for example `\(kind == .constant ? "let" : "state") \(name): Type(value)`."
            )
        } else if explicitType != nil, canStartInlineExpression() {
            throw ParseError(
                "\(kind == .constant ? "let" : "state") '\(name)' expects one initializer after ':'. Use typed construction, for example `\(kind == .constant ? "let" : "state") \(name): \(explicitType!.displayName)(value)`."
            )
        } else if explicitType == nil, typedInitializer == nil, canStartInlineExpression() {
            expression = try parseExpression()
        } else if let typedInitializer {
            expression = typedInitializer
        } else if let explicitType {
            expression = .call(name: explicitType.displayName, arguments: [])
        } else {
            throw ParseError(
                "\(kind == .constant ? "let" : "state") '\(name)' expects typed construction, for example `\(kind == .constant ? "let" : "state") \(name): Type(value)`."
            )
        }
        let resolvedType = try inferInitializedBindingType(
            name: name,
            explicitType: explicitType,
            expression: expression,
            accessibleTypes: accessibleLocalTypes(localBindings),
            bindingKindDescription: kind == .constant ? "let" : "state",
            allowPromiseResolution: kind == .constant
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

    func canStartExpression(_ token: Token) -> Bool {
        switch token {
        case .identifier, .integer, .double, .stringLiteral, .markerAttribute,
            .macroAttribute, .leftBracket, .leftParen, .leftBrace, .dollar, .dot, .bang:
            return true
        case .keyword(let value):
            return !RangeSyntax.keywordIdentifiers.contains(value)
        default:
            return false
        }
    }

    func canStartInlineExpression() -> Bool {
        guard index > 0, index < tokens.count, canStartExpression(peek()) else {
            return false
        }
        return tokens[index - 1].range.end.line == tokens[index].range.start.line
    }

    func rejectAssignmentShapedTypeDeclaration(
        name: String,
        expression: Expression,
        bindingKindDescription: String
    ) throws {
        guard case .identifier(let typeName) = expression,
            isUppercaseTypeReferenceName(typeName),
            canParseTypeReference(typeName)
        else {
            return
        }

        throw ParseError(
            "\(bindingKindDescription) '\(name)' uses assignment-shaped type construction. Use `\(bindingKindDescription) \(name): \(typeName)`."
        )
    }

    func isUppercaseTypeReferenceName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return first.isUppercase
    }

    func canParseTypeReference(_ source: String) -> Bool {
        do {
            var parser = try Parser(source: source)
            _ = try parser.parseTypeReferenceNode()
            try parser.consume(.eof)
            return true
        } catch {
            return false
        }
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
                throw ParseError("Cannot assign to immutable binding '\(name)'.")
            }
            return .local(name)
        }

        if currentMutableStateNames.contains(name) {
            return .state(name)
        }

        if currentBindingNames.contains(name) {
            return .binding(name)
        }

        if currentStateNames.contains(name) {
            throw ParseError("Cannot assign to derived state '\(name)'.")
        }

        throw ParseError("Unknown mutable symbol '\(name)'. Declare it with let or state.")
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
            if case .keyword(RangeSyntax.Keyword.caseBranch.rawValue) = peek() {
                try consumeKeyword(.caseBranch)
                let patterns = try parseSwitchCasePatterns()
                if patterns.count > 1,
                    patterns.contains(where: { pattern in
                        if case .enumCase(_, .some) = pattern { return true }
                        return false
                    })
                {
                    throw ParseError("Switch cases with multiple patterns cannot bind values yet.")
                }
                let body = try parseSwitchBodyStatements(
                    baseLocalBindings: localBindings,
                    pattern: patterns[0]
                )
                cases.append(contentsOf: patterns.map { SwitchCase(pattern: $0, body: body) })
                continue
            }

            if case .keyword(RangeSyntax.Keyword.defaultBranch.rawValue) = peek() {
                try consumeKeyword(.defaultBranch)
                if defaultBody != nil {
                    throw ParseError("Switch can only contain one default block.")
                }
                defaultBody = try parseSwitchBodyStatements(
                    baseLocalBindings: localBindings,
                    pattern: .expression(.identifier("_"))
                )
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

        while peek() == .keyword(RangeSyntax.Keyword.elseBranch.rawValue) {
            try consumeKeyword(.elseBranch)

            if peek() == .keyword(RangeSyntax.Keyword.ifStatement.rawValue) {
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

    mutating func parseSwitchCasePattern() throws -> SwitchCasePattern {
        if peek() == .dot {
            try consume(.dot)
            let name = try consumeCallableName()

            if peek() == .leftParen {
                try consume(.leftParen)
                let bindingKind: LocalBindingKind
                switch peek() {
                case .keyword(RangeSyntax.Keyword.let.rawValue):
                    bindingKind = .constant
                    advance()
                case .keyword(RangeSyntax.Keyword.state.rawValue):
                    bindingKind = .mutable
                    advance()
                default:
                    throw ParseError("Expected let or state in switch case binding.")
                }

                let bindingName = try consumeIdentifier()
                try consume(.rightParen)
                return .enumCase(
                    name: ".\(name)",
                    binding: SwitchCaseBinding(kind: bindingKind, name: bindingName)
                )
            }

            return .enumCase(name: ".\(name)", binding: nil)
        }

        return .expression(try parseExpression())
    }

    mutating func parseSwitchCasePatterns() throws -> [SwitchCasePattern] {
        var patterns = [try parseSwitchCasePattern()]
        while peek() == .comma {
            try consume(.comma)
            patterns.append(try parseSwitchCasePattern())
        }
        return patterns
    }

    mutating func parseSwitchBodyStatements(
        baseLocalBindings: [String: LocalBindingSymbol],
        pattern: SwitchCasePattern
    )
        throws -> [Statement]
    {
        try consume(.colon)

        var localBindings = baseLocalBindings
        if case .enumCase(_, let binding?) = pattern {
            localBindings[binding.name] = LocalBindingSymbol(
                kind: binding.kind,
                type: .named("Never")
            )
        }

        var statements: [Statement] = []
        while true {
            if peek() == .rightBrace {
                break
            }
            if case .keyword(let keyword) = peek(),
                keyword == RangeSyntax.Keyword.caseBranch.rawValue
                    || keyword == RangeSyntax.Keyword.defaultBranch.rawValue
            {
                break
            }
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        return statements
    }

    mutating func parseStatementBlock(baseLocalBindings: [String: LocalBindingSymbol]) throws
        -> [Statement]
    {
        guard peek() == .leftBrace else {
            throw ParseError("Expected block body.")
        }
        try consume(.leftBrace)

        let outerCallableReturnTypes = currentCallableReturnTypes
        defer { currentCallableReturnTypes = outerCallableReturnTypes }

        var localBindings = baseLocalBindings
        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        try consume(.rightBrace)
        return statements
    }

    func isStatementStart() -> Bool {
        if isLocalBackgroundCallableStart() {
            return true
        }
        if isBackgroundStatementStart() {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.ifStatement.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.whileLoop.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.forLoop.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.switchStatement.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.returnStatement.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.breakStatement.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.continueStatement.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.let.rawValue)
            || peek() == .keyword(RangeSyntax.Keyword.state.rawValue)
            || peek() == .keyword(RangeSyntax.Keyword.derived.rawValue)
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
