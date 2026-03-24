import Foundation

public indirect enum Expression {
    case integer(Int)
    case double(Double)
    case string(String)
    case interpolatedString(InterpolatedString)
    case boolean(Bool)
    case none
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
}

public struct DictionaryElement {
    public let key: Expression
    public let value: Expression
}

public enum UnaryOperator: String {
    case not = "!"
}

public enum BinaryOperator: String {
    case addition = "+"
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
