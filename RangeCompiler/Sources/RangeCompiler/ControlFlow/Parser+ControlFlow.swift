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
            return false
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

        return false
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
