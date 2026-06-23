import Foundation

extension Parser {
    mutating func parseStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        let previousClosureBaseLocalBindings = currentClosureBaseLocalBindings
        currentClosureBaseLocalBindings = localBindings
        defer { currentClosureBaseLocalBindings = previousClosureBaseLocalBindings }

        if let targetStatement = targetEmittedCodeStatement() {
            guard currentMacroBodyDepth > 0 else {
                throw ParseError("\(targetStatement.operation) is only valid inside macro bodies.")
            }
            return try parseTargetEmittedCodeStatement(
                targetPath: targetStatement.path,
                operation: targetStatement.operation
            )
        }

        if isLocalBackgroundCallableStart() {
            return try parseLocalBackgroundCallableDeclaration(localBindings: &localBindings)
        }

        if isCallableStart() {
            return try parseLocalCallableDeclaration(localBindings: &localBindings)
        }

        if isBackgroundStatementStart() {
            return try parseBackgroundStatement(localBindings: &localBindings)
        }

        if isMacroApplicationStart()
            || (currentMacroBodyDepth > 0 && {
                if case .macroAttribute = peek() { return true }
                return false
            }())
        {
            return try parseMacroApplicationStatement(localBindings: &localBindings)
        }

        if isDeferStatementStart() {
            return try parseDeferStatement(localBindings: &localBindings)
        }

        if currentMacroBodyDepth == 0, isBareStatementSyntaxStart() {
            throw ParseError(
                "Bare statement syntax is not Range source. Use explicit @statement macros such as @return, @if, @while, @break, @continue, @let, @state, or @assignment."
            )
        }

        if isExpressionStatementStart() {
            return .expression(try parseExpression())
        }

        throw ParseError("Expected statement, found \(peek()).")
    }

    private func isBareStatementSyntaxStart() -> Bool {
        switch peek() {
        case .keyword(RangeSyntax.Keyword.ifStatement.rawValue),
            .keyword(RangeSyntax.Keyword.whileLoop.rawValue),
            .keyword(RangeSyntax.Keyword.forLoop.rawValue),
            .keyword(RangeSyntax.Keyword.switchStatement.rawValue),
            .keyword(RangeSyntax.Keyword.let.rawValue),
            .keyword(RangeSyntax.Keyword.state.rawValue),
            .keyword(RangeSyntax.Keyword.derived.rawValue),
            .keyword(RangeSyntax.Keyword.returnStatement.rawValue),
            .keyword(RangeSyntax.Keyword.breakStatement.rawValue),
            .keyword(RangeSyntax.Keyword.continueStatement.rawValue):
            return true
        default:
            return isColonAssignmentStatementStart() || isAssignmentStatementStart()
        }
    }

    mutating func parseMacroApplicationStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        guard case .macroAttribute(let name, _) = peek() else {
            throw ParseError("Expected macro application statement.")
        }
        advance()
        if peek() == .leftBrace {
            return .macroInvocation(
                name: name,
                argumentClause: nil,
                body: try parseStatementBlock(baseLocalBindings: localBindings)
            )
        }
        if macroArgumentClauseIsFollowedByBlock() {
            let argumentClause = try parseMacroArgumentClauseIfPresent()
            return .macroInvocation(
                name: name,
                argumentClause: argumentClause,
                body: try parseStatementBlock(baseLocalBindings: localBindings)
            )
        }

        var fullName = name
        try appendPostfixAccesses(to: &fullName)
        let arguments = try parseInvocationArgumentsIfPresent()
        if currentMacroBodyDepth > 0, fullName == "assignment" || fullName == "set" {
            return try macroLocalAssignmentStatement(arguments: arguments)
        }
        registerMacroLocalBindingIfPresent(
            macroName: fullName,
            arguments: arguments,
            localBindings: &localBindings
        )
        return .macroApplication(
            name: fullName,
            arguments: arguments
        )
    }

    private func macroLocalAssignmentStatement(arguments: [CallArgument]) throws -> Statement {
        guard let targetArgument = arguments.first(where: { $0.label == "target" })
            ?? arguments.first(where: { $0.label == "name" }),
            case .string(let name) = targetArgument.value,
            !name.isEmpty
        else {
            throw ParseError("@set in a macro body requires name: \"name\".")
        }
        guard let valueArgument = arguments.first(where: { $0.label == "value" }) else {
            throw ParseError("@set in a macro body requires a value argument.")
        }

        return .assignment(target: .local(name), expression: valueArgument.value)
    }

    private func registerMacroLocalBindingIfPresent(
        macroName: String,
        arguments: [CallArgument],
        localBindings: inout [String: LocalBindingSymbol]
    ) {
        guard currentMacroBodyDepth > 0,
            macroName == "state" || macroName == "let",
            let nameArgument = arguments.first(where: { $0.label == "name" }),
            case .string(let name) = nameArgument.value,
            !name.isEmpty
        else {
            return
        }
        localBindings[name] = LocalBindingSymbol(
            kind: macroName == "state" ? .mutable : .constant,
            type: .named("Unknown")
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

    func targetEmittedCodeStatement() -> (path: String, operation: String)? {
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
            let operation = components.last,
            operation == "expand" || operation == "replace",
            peek(offset: offset) == .leftBrace
        else {
            return nil
        }

        return (components.dropLast().joined(separator: "."), operation)
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

    mutating func parseLocalCallableDeclaration(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        _ = localBindings
        let callable = try parseCallableDeclaration()
        guard let body = callable.body else {
            throw ParseError("Local callable \(callable.name) requires a body.")
        }
        return .localCallable(
            LocalCallableDeclaration(
                macros: callable.macros,
                attribute: callable.attribute,
                name: callable.name,
                genericParameters: callable.genericParameters,
                hasExplicitParameterClause: callable.hasExplicitParameterClause,
                parameters: callable.parameters,
                returnType: callable.returnType,
                body: body
            )
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
        return .background(
            Background(
                macros: [MacroApplication(name: name, genericArguments: [], argumentClause: nil)],
                body: body
            )
        )
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

    func isColonAssignmentStatementStart() -> Bool {
        guard case .identifier = peek() else { return false }
        var offset = 1
        while peek(offset: offset) == .dot {
            guard case .identifier = peek(offset: offset + 1) else {
                return false
            }
            offset += 2
        }
        return peek(offset: offset) == .colon
    }

    func isExpressionStatementStart() -> Bool {
        switch peek() {
        case .identifier, .integer, .double, .stringLiteral, .leftBracket,
            .leftParen, .dollar, .dot, .bang:
            return true
        case .hash where peek(offset: 1) == .leftParen:
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

    mutating func parseLocalStateStatement(
        localBindings: inout [String: LocalBindingSymbol]
    ) throws -> Statement {
        guard case .identifier(let name) = peek() else {
            throw ParseError("Expected state name.")
        }

        if isExistingMutableTargetStart(name: name, localBindings: localBindings) {
            let target = try parseAssignmentTarget(localBindings: localBindings)
            try consume(.colon)
            return .assignment(target: target, expression: try parseExpression())
        }

        return try parseLocalDeclaration(kind: .mutable, localBindings: &localBindings)
    }

    func isExistingMutableTargetStart(
        name: String,
        localBindings: [String: LocalBindingSymbol]
    ) -> Bool {
        if currentSelfAvailable, name == "self" {
            return true
        }
        if localBindings[name] != nil {
            return true
        }
        return currentMutableStateNames.contains(name)
            || currentBindingNames.contains(name)
            || currentStateNames.contains(name)
    }

    func canStartExpression(_ token: Token) -> Bool {
        switch token {
        case .identifier, .integer, .double, .stringLiteral, .macroAttribute,
            .leftBracket, .leftParen, .leftBrace, .dollar, .dot, .bang:
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

        if currentMacroBodyDepth > 0 {
            return .local(name)
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
        loopBindings[name] = LocalBindingSymbol(
            kind: .constant,
            type: loopBindingType(for: sequence)
        )
        var body: [Statement] = []
        while peek() != .rightBrace {
            body.append(try parseStatement(localBindings: &loopBindings))
        }

        try consume(.rightBrace)
        return .forEach(name: name, sequence: sequence, body: body)
    }

    private func loopBindingType(for sequence: Expression) -> TypeReference {
        guard case .binary(_, let operatorSymbol, _) = sequence,
            operatorSymbol == .rangeUntil || operatorSymbol == .closedRange
        else {
            return .named("Never")
        }
        return .named("Int")
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
        if isMacroApplicationStart() {
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
