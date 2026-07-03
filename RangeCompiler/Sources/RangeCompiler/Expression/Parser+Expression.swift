import Foundation

private enum ExpressionOperatorAssociativity {
    case none
    case left
    case right
}

extension Parser {
    mutating func parseInvocationArgumentsIfPresent() throws -> [CallArgument] {
        guard peek() == .leftParen else { return [] }
        try consume(.leftParen)
        var arguments: [CallArgument] = []

        if peek() != .rightParen {
            while true {
                arguments.append(try parseInvocationArgument())
                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return arguments
    }

    mutating func parseInvocationArgument() throws -> CallArgument {
        if case .identifier(let label) = peek(), peek(offset: 1) == .colon {
            advance()
            try consume(.colon)
            if peek() == .leftBrace, isClosureExpressionStart() {
                return CallArgument(label: label, value: try parseClosureExpression())
            }
            return CallArgument(label: label, value: try parseExpression())
        }
        if case .keyword(let label) = peek(), peek(offset: 1) == .colon {
            advance()
            try consume(.colon)
            if peek() == .leftBrace, isClosureExpressionStart() {
                return CallArgument(label: label, value: try parseClosureExpression())
            }
            return CallArgument(label: label, value: try parseExpression())
        }
        return CallArgument(label: nil, value: try parseExpression())
    }

    public mutating func parseExpression() throws -> Expression {
        try parseTernaryExpression()
    }

    mutating func parseExpression(terminatingAt terminators: [Token]) throws -> Expression {
        let outerTerminators = currentExpressionTerminators
        currentExpressionTerminators = outerTerminators + terminators
        defer { currentExpressionTerminators = outerTerminators }
        return try parseExpression()
    }

    mutating func parseTernaryExpression() throws -> Expression {
        let condition = try parseBinaryExpression(minimumPrecedence: 0)

        if isCurrentExpressionTerminator(peek()) {
            return condition
        }

        guard peek() == .question else {
            return condition
        }

        try consume(.question)
        let trueExpression = try parseExpression()
        try consume(.colon)
        let falseExpression = try parseExpression()
        return .ternary(
            condition: condition,
            trueExpression: trueExpression,
            falseExpression: falseExpression
        )
    }

    mutating func parseBinaryExpression(minimumPrecedence: Int) throws -> Expression {
        var expression = try parseUnaryExpression()

        while !isCurrentExpressionTerminator(peek()) {
            guard let infix = currentInfixOperatorInfo() else {
                break
            }

            let precedence = infix.precedence
            guard precedence >= minimumPrecedence else {
                break
            }

            advance()
            let nextMinimumPrecedence: Int
            switch infix.associativity {
            case .right:
                nextMinimumPrecedence = precedence
            case .left, .none:
                nextMinimumPrecedence = precedence + 1
            }

            let rhs = try parseBinaryExpression(minimumPrecedence: nextMinimumPrecedence)
            expression = .binary(lhs: expression, operatorSymbol: infix.operatorSymbol, rhs: rhs)
        }

        return expression
    }

    mutating func parseUnaryExpression() throws -> Expression {
        if let unary = currentPrefixOperator() {
            advance()
            return .unary(operatorSymbol: unary, expression: try parseUnaryExpression())
        }
        return try parsePrimaryExpression()
    }

    mutating func parsePrimaryExpression() throws -> Expression {
        switch peek() {
        case .integer(let value):
            advance()
            return .integer(value)
        case .double(let value):
            advance()
            return .double(value)
        case .stringLiteral(let value):
            advance()
            return .string(value)
        case .macroAttribute(let name, _) where isSingleCapturedSyntaxExpressionMacro(name):
            return try parseCapturedSyntaxExpressionMacroInvocation(name: name)
        case .macroAttribute(let name, _):
            advance()
            var fullName = name
            try appendPostfixAccesses(to: &fullName)
            return .macroInvocation(
                name: fullName,
                arguments: try parseInvocationArgumentsIfPresent()
            )
        case .hash where peek(offset: 1) == .leftParen:
            try consume(.hash)
            try consume(.leftParen)
            let expression = try parseExpression(terminatingAt: [.rightParen])
            try consume(.rightParen)
            return .call(
                name: "__syntaxSplice",
                arguments: [CallArgument(label: nil, value: expression)]
            )
        case .identifier(let name), .keyword(let name):
            advance()
            var fullName = name
            try appendPostfixAccesses(to: &fullName)
            return try parseCalledOrReferencedExpression(named: fullName)
        case .dollar:
            try consume(.dollar)
            let name = try consumeIdentifier()
            var fullName = name
            try appendPostfixAccesses(to: &fullName)
            return .bindingReference(fullName)
        case .dot:
            advance()
            let name = try consumeCallableName()
            let fullName = ".\(name)"
            return try parseCalledOrReferencedExpression(named: fullName)
        case .leftParen:
            try consume(.leftParen)
            let expression = try parseExpression()
            try consume(.rightParen)
            return expression
        case .leftBracket:
            return try parseArrayExpression()
        case .leftBrace:
            return .block(try parseStatementBlock())
        default:
            throw ParseError("Expected expression.")
        }
    }

    mutating func parseArrayExpression() throws -> Expression {
        try consume(.leftBracket)
        var elements: [Expression] = []

        if peek() != .rightBracket {
            while true {
                elements.append(try parseExpression(terminatingAt: [.comma, .rightBracket]))
                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightBracket)
        return .array(elements)
    }

    mutating func parseCalledOrReferencedExpression(named fullName: String) throws -> Expression {
        var arguments: [CallArgument] = []
        let hadArgumentClause = peek() == .leftParen

        if hadArgumentClause {
            arguments = try parseInvocationArgumentsIfPresent()
        }

        if peek() == .leftBrace, isClosureExpressionStart() {
            arguments.append(CallArgument(label: nil, value: try parseClosureExpression()))
        }

        guard hadArgumentClause || !arguments.isEmpty else {
            return .identifier(fullName)
        }

        return .call(name: fullName, arguments: arguments)
    }

    func isSingleCapturedSyntaxExpressionMacro(_ name: String) -> Bool {
        guard let macro = macroDeclarationsByName[name] else {
            return false
        }
        return macro.parameters.count == 1 && macro.parameters[0].capturesSyntax
    }

    mutating func parseCapturedSyntaxExpressionMacroInvocation(name: String) throws -> Expression {
        advance()
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
                throw ParseError("Unterminated captured macro argument clause.")
            default:
                parts.append(renderMacroToken(token))
            }
        }

        let rawArgument = parts.joined(separator: " ").trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !rawArgument.isEmpty else {
            throw ParseError("Captured macro argument cannot be empty.")
        }

        return .macroInvocation(
            name: name,
            arguments: [
                CallArgument(label: nil, value: .identifier(rawArgument))
            ]
        )
    }

    func isClosureExpressionStart() -> Bool {
        guard peek() == .leftBrace else {
            return false
        }

        var offset = 1
        while true {
            switch peek(offset: offset) {
            case .identifier, .keyword:
                offset += 1
                switch peek(offset: offset) {
                case .comma:
                    offset += 1
                    continue
                case .keyword("in"):
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }
    }

    mutating func parseClosureExpression() throws -> Expression {
        try consume(.leftBrace)

        var parameterNames: [String] = []
        while true {
            switch peek() {
            case .identifier(let name), .keyword(let name):
                parameterNames.append(name)
                advance()
            default:
                throw ParseError("Expected closure parameter name.")
            }

            if peek() == .comma {
                advance()
                continue
            }

            break
        }

        try consumeKeyword("in")

        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement())
        }

        try consume(.rightBrace)

        return .call(
            name: "Closure",
            arguments: [
                CallArgument(
                    label: "parameters",
                    value: .array(parameterNames.map(Expression.identifier))
                ),
                CallArgument(
                    label: "body",
                    value: .block(statements)
                ),
            ]
        )
    }

    mutating func appendPostfixAccesses(to fullName: inout String) throws {
        while true {
            if peek() == .dot {
                switch peek(offset: 1) {
                case .identifier(let nextName), .keyword(let nextName):
                    advance()
                    advance()
                    fullName += ".\(nextName)"
                    continue
                default:
                    return
                }
            }

            return
        }
    }

    func inferExpressionType(
        of expression: Expression,
        accessibleTypes: [String: TypeReference]
    ) throws -> BootstrapLiteralType {
        let typedAccessibleTypes = accessibleTypes.mapValues { BootstrapLiteralType.typed($0) }
        return try ExpressionTypeSemantics.inferType(
            of: expression,
            accessibleTypes: typedAccessibleTypes,
            callableReturnTypes: [:],
            macroExpansionTypes: macroExpansionTypes,
            resolver: literalBridgeResolver,
            memberResolver: declarationMemberResolver,
            operatorResolver: declarationOperatorResolver,
            macroExpansionResolver: declarationMacroExpansionResolver
        )
    }

    func isNilLiteral(_ expression: Expression) -> Bool {
        ExpressionTypeSemantics.isNilLiteral(expression)
    }

    func defaultDestinationTypeReference(for type: BootstrapLiteralType) -> TypeReference? {
        ExpressionTypeSemantics.defaultDestinationTypeReference(
            for: type,
            resolver: literalBridgeResolver
        )
    }

    func isOptionalExpressionType(_ type: BootstrapLiteralType) -> Bool {
        ExpressionTypeSemantics.isOptionalExpressionType(type)
    }

    func expressionTypesMatch(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType
    ) -> Bool {
        ExpressionTypeSemantics.expressionTypesMatch(lhs, rhs)
    }

    func isCompatibleWithExpectedType(_ actual: BootstrapLiteralType, expected: TypeReference)
        -> Bool
    {
        ExpressionTypeSemantics.isCompatible(
            actual: actual,
            expected: expected,
            resolver: literalBridgeResolver
        )
    }

    func isCompatibleNamedType(expected: TypeReference, actual: TypeReference) -> Bool {
        ExpressionTypeSemantics.isCompatibleNamedType(expected: expected, actual: actual)
    }

    private func currentPrefixOperator() -> UnaryOperator? {
        guard let symbol = operatorSymbol(for: peek()) else {
            return nil
        }
        switch symbol {
        case "!":
            return .not
        default:
            return nil
        }
    }

    private func currentInfixOperatorInfo() -> (
        operatorSymbol: BinaryOperator, precedence: Int,
        associativity: ExpressionOperatorAssociativity
    )? {
        guard let symbol = operatorSymbol(for: peek()) else {
            return nil
        }

        guard let operatorSymbol = binaryOperator(for: symbol) else {
            return nil
        }
        guard let bindingPower = expressionOperatorBindingPower(for: symbol) else {
            return nil
        }

        return (
            operatorSymbol: operatorSymbol,
            precedence: bindingPower.precedence,
            associativity: bindingPower.associativity
        )
    }

    private func expressionOperatorBindingPower(for symbol: String) -> (
        precedence: Int,
        associativity: ExpressionOperatorAssociativity
    )? {
        switch symbol {
        case "||":
            return (0, .left)
        case "&&":
            return (1, .left)
        case "==", "!=", "<", "<=", ">", ">=":
            return (2, .none)
        case "..<", "...":
            return (3, .none)
        case "??":
            return (4, .right)
        case "+", "-":
            return (5, .left)
        case "*", "/", "%":
            return (6, .left)
        default:
            return nil
        }
    }

    private func operatorSymbol(for token: Token) -> String? {
        switch token {
        case .minus:
            return "-"
        case .plus:
            return "+"
        case .asterisk:
            return "*"
        case .slash:
            return "/"
        case .percent:
            return "%"
        case .questionQuestion:
            return "??"
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
        case .andAnd:
            return "&&"
        case .orOr:
            return "||"
        case .bang:
            return "!"
        case .ellipsis:
            return "..."
        case .dotDotLess:
            return "..<"
        default:
            return nil
        }
    }

    private func binaryOperator(for symbol: String) -> BinaryOperator? {
        switch symbol {
        case "+":
            return .addition
        case "-":
            return .subtraction
        case "*":
            return .multiplication
        case "/":
            return .division
        case "%":
            return .remainder
        case "??":
            return .nilCoalescing
        case "==":
            return .equal
        case "!=":
            return .notEqual
        case "<":
            return .less
        case "<=":
            return .lessEqual
        case ">":
            return .greater
        case ">=":
            return .greaterEqual
        case "&&":
            return .and
        case "||":
            return .or
        case "..<":
            return .rangeUntil
        case "...":
            return .closedRange
        default:
            return nil
        }
    }
}
