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
            if peek() == .leftParen {
                return .call(name: fullName, arguments: try parseInvocationArgumentsIfPresent())
            }
            return .identifier(fullName)
        case .dollar:
            try consume(.dollar)
            return .bindingReference(try consumeIdentifier())
        case .dot:
            advance()
            let name = try consumeCallableName()
            var fullName = ".\(name)"
            fullName += try parseGenericArgumentClauseIfPresent()
            if peek() == .leftParen {
                return .call(name: fullName, arguments: try parseInvocationArgumentsIfPresent())
            }
            return .identifier(fullName)
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
        guard peek() == .less else {
            return ""
        }

        try consume(.less)
        var arguments: [String] = [try consumeTypeReference()]
        while peek() == .comma {
            advance()
            arguments.append(try consumeTypeReference())
        }
        try consume(.greater)
        return "<\(arguments.joined(separator: ", "))>"
    }

    func inferBootstrapExpressionType(
        of expression: Expression,
        accessibleTypes: [String: TypeReference]
    ) throws -> BootstrapLiteralType {
        let bootstrapAccessibleTypes = accessibleTypes.mapValues { BootstrapLiteralType.typed($0) }
        return try BootstrapExpressionSemantics.inferType(
            of: expression,
            accessibleTypes: bootstrapAccessibleTypes
        )
    }

    func isNilLiteral(_ expression: Expression) -> Bool {
        BootstrapExpressionSemantics.isNilLiteral(expression)
    }

    func bootstrapLiteralBridge(for type: BootstrapLiteralType) -> BootstrapLiteralBridge? {
        switch type {
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            return BootstrapLiteralRegistry.bridge(for: type)
        case .typed:
            return nil
        }
    }

    func defaultDestinationTypeReference(for type: BootstrapLiteralType) -> TypeReference? {
        BootstrapExpressionSemantics.defaultDestinationTypeReference(
            for: type,
            resolver: literalBridgeResolver
        )
    }

    func isOptionalBootstrapExpressionType(_ type: BootstrapLiteralType) -> Bool {
        BootstrapExpressionSemantics.isOptionalExpressionType(type)
    }

    func bootstrapExpressionTypesMatch(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType
    ) -> Bool {
        BootstrapExpressionSemantics.expressionTypesMatch(lhs, rhs)
    }

    func isCompatibleWithExpectedType(_ actual: BootstrapLiteralType, expected: TypeReference)
        -> Bool
    {
        BootstrapExpressionSemantics.isCompatible(
            actual: actual,
            expected: expected,
            resolver: literalBridgeResolver
        )
    }

    func isCompatibleNamedType(expected: TypeReference, actual: TypeReference) -> Bool {
        BootstrapExpressionSemantics.isCompatibleNamedType(expected: expected, actual: actual)
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
        case .plus:
            return "+"
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
        default:
            return nil
        }
    }

    func binaryOperator(for symbol: String) -> BinaryOperator? {
        switch symbol {
        case "+":
            return .addition
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
        default:
            return nil
        }
    }
}
