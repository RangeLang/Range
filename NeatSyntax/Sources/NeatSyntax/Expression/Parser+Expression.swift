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
            var parts = [name]
            parseMembers: while peek() == .dot {
                switch peek(offset: 1) {
                case .identifier(let nextName), .keyword(let nextName):
                    advance()
                    advance()
                    parts.append(nextName)
                default:
                    break parseMembers
                }
            }
            var fullName = parts.joined(separator: ".")
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

                var parser = try? Parser(source: expressionText)
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
        switch expression {
        case .integer:
            return .intLiteral
        case .double:
            return .floatLiteral
        case .string:
            return .stringLiteral
        case .interpolatedString:
            return .stringLiteral
        case .boolean:
            return .boolLiteral
        case .nilLiteral:
            return .nilLiteral
        case .block:
            throw ParseError(
                "Block expressions are not supported in state initializer inference yet.")
        case .identifier(let name):
            guard let type = accessibleTypes[name] else {
                throw ParseError("Unknown identifier '\(name)' in state initializer.")
            }
            return .typed(type)
        case .call:
            throw ParseError(
                "Callable expressions are not supported in state initializer inference yet.")
        case .bindingReference(let name):
            throw ParseError("Binding reference '$\(name)' is not valid in a state initializer.")
        case .array:
            throw ParseError("Array type inference is not supported in state initializers yet.")
        case .dictionary:
            throw ParseError(
                "Dictionary type inference is not supported in state initializers yet.")
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionType = try inferBootstrapExpressionType(
                of: condition,
                accessibleTypes: accessibleTypes
            )
            guard isCompatibleWithExpectedType(conditionType, expected: .named("Bool")) else {
                throw ParseError(
                    "Ternary condition must be Bool, got \(conditionType.displayName).")
            }
            if isNilLiteral(trueExpression) {
                let falseType = try inferBootstrapExpressionType(
                    of: falseExpression,
                    accessibleTypes: accessibleTypes
                )
                guard isOptionalBootstrapExpressionType(falseType) else {
                    throw ParseError(
                        "Ternary branches must match, got nil and \(falseType.displayName)."
                    )
                }
                return falseType
            }
            if isNilLiteral(falseExpression) {
                let trueType = try inferBootstrapExpressionType(
                    of: trueExpression,
                    accessibleTypes: accessibleTypes
                )
                guard isOptionalBootstrapExpressionType(trueType) else {
                    throw ParseError(
                        "Ternary branches must match, got \(trueType.displayName) and nil."
                    )
                }
                return trueType
            }
            let trueType = try inferBootstrapExpressionType(
                of: trueExpression,
                accessibleTypes: accessibleTypes
            )
            let falseType = try inferBootstrapExpressionType(
                of: falseExpression,
                accessibleTypes: accessibleTypes
            )
            guard bootstrapExpressionTypesMatch(trueType, falseType) else {
                throw ParseError(
                    "Ternary branches must match, got \(trueType.displayName) and \(falseType.displayName)."
                )
            }
            return trueType
        case .unary(let operatorSymbol, _):
            switch operatorSymbol {
            case .not:
                throw ParseError(
                    "Unary operator typing is not supported by bootstrap inference yet.")
            }
        case .binary(_, let operatorSymbol, _):
            switch operatorSymbol {
            case .addition:
                throw ParseError(
                    "Binary operator typing is not supported by bootstrap inference yet.")
            case .nilCoalescing:
                throw ParseError(
                    "Binary operator typing is not supported by bootstrap inference yet.")
            case .equal, .notEqual:
                throw ParseError(
                    "Binary operator typing is not supported by bootstrap inference yet.")
            case .less, .lessEqual, .greater, .greaterEqual:
                throw ParseError(
                    "Binary operator typing is not supported by bootstrap inference yet.")
            case .and, .or:
                throw ParseError(
                    "Binary operator typing is not supported by bootstrap inference yet.")
            }
        }
    }

    func isNilLiteral(_ expression: Expression) -> Bool {
        if case .nilLiteral = expression { return true }
        return false
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
        switch type {
        case .typed(let typeReference):
            return typeReference
        default:
            return bootstrapLiteralBridge(for: type)?.defaultDestinationType
        }
    }

    func isOptionalBootstrapExpressionType(_ type: BootstrapLiteralType) -> Bool {
        switch type {
        case .nilLiteral:
            return true
        case .typed(let typeReference):
            if case .optional = typeReference {
                return true
            }
            return false
        default:
            return false
        }
    }

    func bootstrapExpressionTypesMatch(
        _ lhs: BootstrapLiteralType,
        _ rhs: BootstrapLiteralType
    ) -> Bool {
        switch (lhs, rhs) {
        case (.intLiteral, .intLiteral),
            (.floatLiteral, .floatLiteral),
            (.stringLiteral, .stringLiteral),
            (.boolLiteral, .boolLiteral),
            (.nilLiteral, .nilLiteral):
            return true
        case (.typed(let lhsType), .typed(let rhsType)):
            return lhsType == rhsType || isCompatibleNamedType(expected: lhsType, actual: rhsType)
        default:
            return false
        }
    }

    func isCompatibleWithExpectedType(_ actual: BootstrapLiteralType, expected: TypeReference)
        -> Bool
    {
        switch actual {
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            guard let bridge = bootstrapLiteralBridge(for: actual) else {
                return false
            }
            if bridge.requiresOptionalContext {
                if case .optional = expected {
                    return true
                }
                return false
            }
            return bridge.acceptedDestinationTypeNames.contains(expected.displayName)
        case .typed(let actualType):
            return actualType == expected
                || isCompatibleNamedType(expected: expected, actual: actualType)
        }
    }

    func isCompatibleNamedType(expected: TypeReference, actual: TypeReference) -> Bool {
        if expected == actual {
            return true
        }
        if expected.displayName == "Float" && actual.displayName == "Double" {
            return true
        }
        return false
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
