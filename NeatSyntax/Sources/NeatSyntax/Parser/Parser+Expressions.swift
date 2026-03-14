import Foundation

extension Parser {
    mutating func parseExpression() throws -> Expression {
        try parseTernaryExpression()
    }

    mutating func parseTernaryExpression() throws -> Expression {
        let condition = try parseLogicalOrExpression()

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
            return .string(value)
        case .identifier(let name):
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
            while peek() == .dot, case .identifier(let nextName) = peek(offset: 1) {
                advance()
                advance()
                parts.append(nextName)
            }
            let fullName = parts.joined(separator: ".")
            if peek() == .leftParen {
                return .call(name: fullName, arguments: try parseInvocationArgumentsIfPresent())
            }
            return .identifier(fullName)
        case .dollar:
            try consume(.dollar)
            return .bindingReference(try consumeIdentifier())
        case .dot:
            advance()
            let name = try consumeIdentifier()
            let fullName = ".\(name)"
            if peek() == .leftParen {
                return .call(name: fullName, arguments: try parseInvocationArgumentsIfPresent())
            }
            return .identifier(fullName)
        case .leftBracket:
            return try parseArrayLiteral()
        case .leftParen:
            try consume(.leftParen)
            let expression = try parseExpression()
            try consume(.rightParen)
            return expression
        default:
            throw ParseError("Expected expression.")
        }
    }

    mutating func parseArrayLiteral() throws -> Expression {
        try consume(.leftBracket)

        var elements: [Expression] = []
        if peek() != .rightBracket {
            while true {
                elements.append(try parseExpression())
                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightBracket)
        return .array(elements)
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
        case "String":
            return .string
        case "Bool":
            return .bool
        case "Dictionary":
            return .dictionary
        case "Void":
            return .void
        default:
            return nil
        }
    }

    func inferType(
        of expression: Expression,
        stateTypes: [String: BuiltinType]
    ) throws -> BuiltinType {
        switch expression {
        case .integer:
            return .int
        case .double:
            throw ParseError(
                "Floating-point type inference is not supported in state initializers yet.")
        case .string:
            return .string
        case .boolean:
            return .bool
        case .none:
            return .none
        case .identifier(let name):
            guard let type = stateTypes[name] else {
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
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionType = try inferType(of: condition, stateTypes: stateTypes)
            guard conditionType == .bool else {
                throw ParseError(
                    "Ternary condition must be Bool, got \(conditionType.displayName).")
            }
            let trueType = try inferType(of: trueExpression, stateTypes: stateTypes)
            let falseType = try inferType(of: falseExpression, stateTypes: stateTypes)
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
            let nestedType = try inferType(of: nested, stateTypes: stateTypes)
            switch operatorSymbol {
            case .not:
                guard nestedType == .bool else {
                    throw ParseError("Operator '!' requires Bool, got \(nestedType.displayName).")
                }
                return .bool
            }
        case .binary(let lhs, let operatorSymbol, let rhs):
            let lhsType = try inferType(of: lhs, stateTypes: stateTypes)
            let rhsType = try inferType(of: rhs, stateTypes: stateTypes)

            switch operatorSymbol {
            case .addition:
                guard lhsType == rhsType else {
                    throw ParseError(
                        "Type mismatch in '+': \(lhsType.displayName) and \(rhsType.displayName).")
                }
                guard lhsType == .int || lhsType == .string else {
                    throw ParseError(
                        "Operator '+' is only supported for Int and String, got \(lhsType.displayName)."
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
                guard lhsType == .int, rhsType == .int else {
                    throw ParseError(
                        "Operator '\(operatorSymbol.rawValue)' is only supported for Int."
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
