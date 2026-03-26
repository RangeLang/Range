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

    mutating func parseTernaryExpression() throws -> Expression {
        let condition = try parseNilCoalescingExpression()

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

    mutating func parseNilCoalescingExpression() throws -> Expression {
        var expression = try parseLogicalOrExpression()

        while peek() == .questionQuestion {
            advance()
            let rhs = try parseLogicalOrExpression()
            expression = .binary(lhs: expression, operatorSymbol: .nilCoalescing, rhs: rhs)
        }

        return expression
    }

    mutating func parseLogicalOrExpression() throws -> Expression {
        var expression = try parseLogicalAndExpression()

        while peek() == .orOr {
            advance()
            let rhs = try parseLogicalAndExpression()
            expression = .binary(lhs: expression, operatorSymbol: .or, rhs: rhs)
        }

        return expression
    }

    mutating func parseLogicalAndExpression() throws -> Expression {
        var expression = try parseEqualityExpression()

        while peek() == .andAnd {
            advance()
            let rhs = try parseEqualityExpression()
            expression = .binary(lhs: expression, operatorSymbol: .and, rhs: rhs)
        }

        return expression
    }

    mutating func parseEqualityExpression() throws -> Expression {
        var expression = try parseComparisonExpression()

        while true {
            switch peek() {
            case .equalEqual:
                advance()
                let rhs = try parseComparisonExpression()
                expression = .binary(lhs: expression, operatorSymbol: .equal, rhs: rhs)
            case .bangEqual:
                advance()
                let rhs = try parseComparisonExpression()
                expression = .binary(lhs: expression, operatorSymbol: .notEqual, rhs: rhs)
            default:
                return expression
            }
        }
    }

    mutating func parseComparisonExpression() throws -> Expression {
        var expression = try parseAdditiveExpression()

        while true {
            switch peek() {
            case .less:
                advance()
                let rhs = try parseAdditiveExpression()
                expression = .binary(lhs: expression, operatorSymbol: .less, rhs: rhs)
            case .lessEqual:
                advance()
                let rhs = try parseAdditiveExpression()
                expression = .binary(lhs: expression, operatorSymbol: .lessEqual, rhs: rhs)
            case .greater:
                advance()
                let rhs = try parseAdditiveExpression()
                expression = .binary(lhs: expression, operatorSymbol: .greater, rhs: rhs)
            case .greaterEqual:
                advance()
                let rhs = try parseAdditiveExpression()
                expression = .binary(lhs: expression, operatorSymbol: .greaterEqual, rhs: rhs)
            default:
                return expression
            }
        }
    }

    mutating func parseAdditiveExpression() throws -> Expression {
        var expression = try parseUnaryExpression()

        while peek() == .plus {
            advance()
            let rhs = try parseUnaryExpression()
            expression = .binary(lhs: expression, operatorSymbol: .addition, rhs: rhs)
        }

        return expression
    }

    mutating func parseUnaryExpression() throws -> Expression {
        switch peek() {
        case .bang:
            advance()
            return .unary(operatorSymbol: .not, expression: try parseUnaryExpression())
        default:
            return try parsePrimaryExpression()
        }
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
            if name == "none" || name == "nil" {
                return .none
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

    mutating func parseBuiltinType() throws -> BuiltinType {
        let raw = try consumeTypeReference()
        guard let type = builtinType(from: raw) else {
            throw ParseError(
                "Unsupported type '\(raw)'. Built-in types: \(NeatSyntax.builtinTypeNames.joined(separator: ", "))."
            )
        }
        return type
    }

    func builtinType(from raw: String) -> BuiltinType? {
        if raw.hasSuffix("?") {
            let base = String(raw.dropLast())
            guard let wrapped = builtinType(from: base) else {
                return nil
            }
            return .optional(wrapped)
        }

        switch raw {
        case "Int":
            return .int
        case "Double":
            return .double
        case "Float":
            return .float
        case "String":
            return .string
        case "Bool":
            return .bool
        case "Data":
            return .data
        case "Dictionary":
            return .dictionary
        case "Void":
            return .void
        default:
            break
        }

        if raw.hasPrefix("Set<"), raw.hasSuffix(">") {
            let start = raw.index(raw.startIndex, offsetBy: 4)
            let end = raw.index(before: raw.endIndex)
            let innerRaw = String(raw[start..<end])
            guard let element = builtinType(from: innerRaw) else {
                return nil
            }
            return .set(element)
        }

        return nil
    }

    func inferType(
        of expression: Expression,
        accessibleTypes: [String: BuiltinType]
    ) throws -> BuiltinType {
        switch expression {
        case .integer:
            return .int
        case .double:
            return .double
        case .string:
            return .string
        case .interpolatedString:
            return .string
        case .boolean:
            return .bool
        case .none:
            return .none
        case .identifier(let name):
            guard let type = accessibleTypes[name] else {
                throw ParseError("Unknown identifier '\(name)' in state initializer.")
            }
            return type
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
            let conditionType = try inferType(of: condition, accessibleTypes: accessibleTypes)
            guard conditionType == .bool else {
                throw ParseError(
                    "Ternary condition must be Bool, got \(conditionType.displayName).")
            }
            let trueType = try inferType(of: trueExpression, accessibleTypes: accessibleTypes)
            let falseType = try inferType(of: falseExpression, accessibleTypes: accessibleTypes)
            if trueType == .none, falseType.isOptional {
                return falseType
            }
            if falseType == .none, trueType.isOptional {
                return trueType
            }
            guard trueType == falseType else {
                throw ParseError(
                    "Ternary branches must match, got \(trueType.displayName) and \(falseType.displayName)."
                )
            }
            return trueType
        case .unary(let operatorSymbol, let nested):
            let nestedType = try inferType(of: nested, accessibleTypes: accessibleTypes)
            switch operatorSymbol {
            case .not:
                guard nestedType == .bool else {
                    throw ParseError("Operator '!' requires Bool, got \(nestedType.displayName).")
                }
                return .bool
            }
        case .binary(let lhs, let operatorSymbol, let rhs):
            let lhsType = try inferType(of: lhs, accessibleTypes: accessibleTypes)
            let rhsType = try inferType(of: rhs, accessibleTypes: accessibleTypes)

            switch operatorSymbol {
            case .addition:
                if lhsType == .string && rhsType == .string {
                    return .string
                }
                if lhsType == .int && rhsType == .int {
                    return .int
                }
                if lhsType == .double && rhsType == .double {
                    return .double
                }
                if (lhsType == .int && rhsType == .double)
                    || (lhsType == .double && rhsType == .int)
                {
                    return .double
                }
                if lhsType == .float && rhsType == .float {
                    return .float
                }
                if (lhsType == .float && rhsType == .int)
                    || (lhsType == .int && rhsType == .float)
                {
                    return .float
                }
                if (lhsType == .float && rhsType == .double)
                    || (lhsType == .double && rhsType == .float)
                {
                    return .double
                }
                throw ParseError(
                    "Operator '+' is only supported for Int, Float, Double, and String, got \(lhsType.displayName) and \(rhsType.displayName)."
                )
            case .nilCoalescing:
                if lhsType == .none {
                    return rhsType
                }
                if rhsType == .none {
                    return lhsType
                }
                if case .optional(let wrapped) = lhsType {
                    guard wrapped == rhsType else {
                        throw ParseError(
                            "Operator '??' requires the right-hand side to match \(wrapped.displayName), got \(rhsType.displayName)."
                        )
                    }
                    return wrapped
                }
                guard lhsType == rhsType else {
                    throw ParseError(
                        "Operator '??' requires compatible types, got \(lhsType.displayName) and \(rhsType.displayName)."
                    )
                }
                return lhsType
            case .equal, .notEqual:
                if lhsType == .none, rhsType.isOptional {
                    return .bool
                }
                if rhsType == .none, lhsType.isOptional {
                    return .bool
                }
                guard lhsType == rhsType else {
                    throw ParseError(
                        "Type mismatch in '\(operatorSymbol.rawValue)': \(lhsType.displayName) and \(rhsType.displayName)."
                    )
                }
                return .bool
            case .less, .lessEqual, .greater, .greaterEqual:
                let isNumericComparison =
                    (lhsType == .int || lhsType == .float || lhsType == .double)
                    && (rhsType == .int || rhsType == .float || rhsType == .double)
                guard isNumericComparison else {
                    throw ParseError(
                        "Operator '\(operatorSymbol.rawValue)' is only supported for Int, Float, and Double."
                    )
                }
                return .bool
            case .and, .or:
                guard lhsType == .bool, rhsType == .bool else {
                    throw ParseError(
                        "Operator '\(operatorSymbol.rawValue)' requires Bool operands."
                    )
                }
                return .bool
            }
        }
    }
}
