import Foundation

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

    mutating func parseExpression() throws -> Expression {
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

            let precedence = operatorEnvironment.precedence(of: infix.precedenceGroup)
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
            if value.contains("\\(") {
                return .interpolatedString(parseInterpolatedString(value))
            }
            return .string(value)
        case .macroAttribute(let name, _) where isSingleCapturedSyntaxExpressionMacro(name):
            return try parseCapturedSyntaxExpressionMacroInvocation(name: name)
        case .macroAttribute(let name, _) where isMacroApplicationAttribute(name):
            advance()
            return .macroInvocation(
                name: name,
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
            if name == "true" {
                return .boolean(true)
            }
            if name == "false" {
                return .boolean(false)
            }
            if name == "nil" {
                return .nilLiteral
            }
            var fullName = name
            try appendPostfixAccesses(to: &fullName)
            fullName += try parseGenericArgumentClauseIfPresent()
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
            var fullName = ".\(name)"
            fullName += try parseGenericArgumentClauseIfPresent()
            return try parseCalledOrReferencedExpression(named: fullName)
        case .leftBracket:
            return try parseCollectionLiteral()
        case .leftParen:
            try consume(.leftParen)
            let expression = try parseExpression()
            try consume(.rightParen)
            return expression
        case .leftBrace:
            return .block(try parseStatementBlock(baseLocalBindings: [:]))
        default:
            throw ParseError("Expected expression.")
        }
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
                case .keyword(RangeSyntax.Keyword.inKeyword.rawValue):
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

        try consumeKeyword(.inKeyword)

        var localBindings = currentClosureBaseLocalBindings
        for (name, binding) in Dictionary(
            uniqueKeysWithValues: parameterNames.map {
                ($0, LocalBindingSymbol(kind: .constant, type: .named("Unknown")))
            }
        ) {
            localBindings[name] = binding
        }
        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
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

            if peek() == .leftBracket {
                try consume(.leftBracket)
                guard case .integer(let index) = peek() else {
                    throw ParseError("Expected integer index.")
                }
                advance()
                try consume(.rightBracket)
                fullName += "[\(index)]"
                continue
            }

            return
        }
    }

    func parseInterpolatedString(_ value: String) -> InterpolatedString {
        var segments: [StringSegment] = []
        var currentText = ""
        let characters = Array(value)
        var index = 0

        func flushText() {
            guard !currentText.isEmpty else { return }
            segments.append(.text(currentText))
            currentText.removeAll(keepingCapacity: true)
        }

        while index < characters.count {
            let character = characters[index]
            if character == "\\" && index + 1 < characters.count && characters[index + 1] == "(" {
                flushText()
                index += 2
                var expressionText = ""
                var depth = 1

                while index < characters.count {
                    let current = characters[index]
                    if current == "(" {
                        depth += 1
                    } else if current == ")" {
                        depth -= 1
                        if depth == 0 {
                            index += 1
                            break
                        }
                    }

                    expressionText.append(current)
                    index += 1
                }

                var parser = try? Parser(
                    source: expressionText,
                    literalBridgeResolver: literalBridgeResolver
                )
                if let expression = try? parser?.parseExpression() {
                    segments.append(.expression(expression))
                } else {
                    segments.append(.text("\\(\(expressionText))"))
                }
                continue
            }

            currentText.append(character)
            index += 1
        }

        flushText()
        return InterpolatedString(segments: segments)
    }

    mutating func parseCollectionLiteral() throws -> Expression {
        try consume(.leftBracket)

        if peek() == .colon {
            try consume(.colon)
            try consume(.rightBracket)
            return .dictionary([])
        }

        if peek() == .rightBracket {
            try consume(.rightBracket)
            return .array([])
        }

        let firstExpression = try parseExpression()
        if peek() == .colon {
            advance()
            let firstValue = try parseExpression()
            var elements = [DictionaryElement(key: firstExpression, value: firstValue)]

            while peek() == .comma {
                advance()
                guard peek() != .rightBracket else { break }
                let key = try parseExpression()
                try consume(.colon)
                let value = try parseExpression()
                elements.append(DictionaryElement(key: key, value: value))
            }

            try consume(.rightBracket)
            return .dictionary(elements)
        }

        var elements: [Expression] = [firstExpression]
        while peek() == .comma {
            advance()
            guard peek() != .rightBracket else { break }
            elements.append(try parseExpression())
        }

        try consume(.rightBracket)
        return .array(elements)
    }

    mutating func parseGenericArgumentClauseIfPresent() throws -> String {
        guard peek() == .less, isGenericArgumentClauseStart() else {
            return ""
        }

        try consume(.less)
        var arguments: [String] = [try parseGenericArgumentReferenceNode().displayName]
        while peek() == .comma {
            advance()
            arguments.append(try parseGenericArgumentReferenceNode().displayName)
        }
        try consume(.greater)
        return "<\(arguments.joined(separator: ", "))>"
    }

    func isGenericArgumentClauseStart() -> Bool {
        switch peek(offset: 1) {
        case .identifier, .keyword, .integer, .double, .stringLiteral, .dot, .leftBracket,
            .leftParen:
            break
        default:
            return false
        }

        var offset = 1
        var depth = 1
        while true {
            switch peek(offset: offset) {
            case .less:
                depth += 1
            case .greater:
                depth -= 1
                if depth == 0 {
                    return true
                }
            case .eof, .leftBrace, .rightBrace, .rightParen, .rightBracket, .equal, .equalEqual,
                .bangEqual, .minus, .lessEqual, .greaterEqual, .plus, .plusEqual, .slash,
                .ampersand, .andAnd, .pipe, .orOr, .dotDotLess,
                .questionQuestion, .colon, .arrow:
                return false
            case .hash, .foreignBody, .macroAttribute, .dollar, .percent, .bang:
                return false
            case .identifier, .keyword, .stringLiteral, .integer, .double,
                .leftBracket, .leftParen, .asterisk, .dot, .ellipsis, .question, .comma:
                break
            }
            offset += 1
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
            callableReturnTypes: currentCallableReturnTypes,
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

    func currentPrefixOperator() -> UnaryOperator? {
        guard let symbol = operatorSymbol(for: peek()) else {
            return nil
        }
        guard operatorEnvironment.prefixOperators.contains(symbol) else {
            return nil
        }

        switch symbol {
        case "!":
            return .not
        default:
            return nil
        }
    }

    func currentInfixOperatorInfo() -> (
        operatorSymbol: BinaryOperator, precedenceGroup: String,
        associativity: OperatorAssociativity
    )? {
        guard let symbol = operatorSymbol(for: peek()) else {
            return nil
        }
        guard let declaration = operatorEnvironment.infixOperators[symbol],
            let precedenceGroup = declaration.precedenceGroup,
            let group = operatorEnvironment.precedenceGroups[precedenceGroup]
        else {
            return nil
        }

        guard let operatorSymbol = binaryOperator(for: symbol) else {
            return nil
        }

        return (
            operatorSymbol: operatorSymbol,
            precedenceGroup: precedenceGroup,
            associativity: group.associativity ?? .none
        )
    }

    func operatorSymbol(for token: Token) -> String? {
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

    func binaryOperator(for symbol: String) -> BinaryOperator? {
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
