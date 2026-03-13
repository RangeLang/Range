import Foundation

extension Parser {
    mutating func parseExpression() throws -> Expression {
        var expression = try parsePrimaryExpression()

        while peek() == .plus {
            advance()
            let rhs = try parsePrimaryExpression()
            expression = .binary(lhs: expression, operatorSymbol: .addition, rhs: rhs)
        }

        return expression
    }

    mutating func parsePrimaryExpression() throws -> Expression {
        switch peek() {
        case .integer(let value):
            advance()
            return .integer(value)
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
            var parts = [name]
            while peek() == .dot, case .identifier(let nextName) = peek(offset: 1) {
                advance()
                advance()
                parts.append(nextName)
            }
            return .identifier(parts.joined(separator: "."))
        case .dot:
            advance()
            let name = try consumeIdentifier()
            return .identifier(".\(name)")
        case .leftBracket:
            return try parseArrayLiteral()
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
        guard let type = BuiltinType(rawValue: raw) else {
            throw ParseError(
                "Unsupported type '\(raw)'. Built-in types: \(NeatSyntax.builtinTypeNames.joined(separator: ", "))."
            )
        }
        return type
    }

    func inferType(
        of expression: Expression,
        stateTypes: [String: BuiltinType]
    ) throws -> BuiltinType {
        switch expression {
        case .integer:
            return .int
        case .string:
            return .string
        case .boolean:
            return .bool
        case .identifier(let name):
            guard let type = stateTypes[name] else {
                throw ParseError("Unknown identifier '\(name)' in @State initializer.")
            }
            return type
        case .binary(let lhs, .addition, let rhs):
            let lhsType = try inferType(of: lhs, stateTypes: stateTypes)
            let rhsType = try inferType(of: rhs, stateTypes: stateTypes)
            guard lhsType == rhsType else {
                throw ParseError(
                    "Type mismatch in '+': \(lhsType.rawValue) and \(rhsType.rawValue).")
            }
            guard lhsType == .int || lhsType == .string else {
                throw ParseError(
                    "Operator '+' is only supported for Int and String, got \(lhsType.rawValue)."
                )
            }
            return lhsType
        case .array:
            throw ParseError("Array type inference is not supported in @State initializers yet.")
        }
    }
}
