import Foundation

public indirect enum Expression {
    case integer(Int)
    case double(Double)
    case string(String)
    case interpolatedString(InterpolatedString)
    case boolean(Bool)
    case nilLiteral
    case macroInvocation(name: String, arguments: [CallArgument])
    case block([Statement])
    case identifier(String)
    case call(name: String, arguments: [CallArgument])
    case bindingReference(String)
    case array([Expression])
    case dictionary([DictionaryElement])
    case ternary(condition: Expression, trueExpression: Expression, falseExpression: Expression)
    case unary(operatorSymbol: UnaryOperator, expression: Expression)
    case binary(lhs: Expression, operatorSymbol: BinaryOperator, rhs: Expression)
}

public struct CallArgument {
    public let label: String?
    public let value: Expression

    public init(label: String?, value: Expression) {
        self.label = label
        self.value = value
    }
}

public struct DictionaryElement {
    public let key: Expression
    public let value: Expression

    public init(key: Expression, value: Expression) {
        self.key = key
        self.value = value
    }
}

public enum UnaryOperator: String {
    case not = "!"
}

public enum BinaryOperator: String {
    case addition = "+"
    case subtraction = "-"
    case multiplication = "*"
    case division = "/"
    case remainder = "%"
    case nilCoalescing = "??"
    case equal = "=="
    case notEqual = "!="
    case less = "<"
    case lessEqual = "<="
    case greater = ">"
    case greaterEqual = ">="
    case and = "&&"
    case or = "||"
}

public struct InterpolatedString {
    public let segments: [StringSegment]

    public init(segments: [StringSegment]) {
        self.segments = segments
    }
}

public indirect enum StringSegment {
    case text(String)
    case expression(Expression)
}
