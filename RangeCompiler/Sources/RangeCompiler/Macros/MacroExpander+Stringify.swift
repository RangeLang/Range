import Foundation

extension MacroExpander {
    static func renderExpressionForStringify(_ expression: Expression) -> String {
        switch expression {
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return "\"\(value)\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .macroInvocation(let name, let arguments):
            return "#\(name)(\(renderArgumentsForStringify(arguments)))"
        case .block:
            return "{ ... }"
        case .identifier(let name):
            return name
        case .call(let name, let arguments):
            if name == "__syntaxSplice",
                arguments.count == 1,
                arguments[0].label == nil
            {
                return "#(\(renderExpressionForStringify(arguments[0].value)))"
            }
            return "\(name)(\(renderArgumentsForStringify(arguments)))"
        case .bindingReference(let name):
            return "$\(name)"
        case .array(let elements):
            return "[\(elements.map(renderExpressionForStringify).joined(separator: ", "))]"
        case .dictionary(let elements):
            let rendered = elements.map {
                "\(renderExpressionForStringify($0.key)): \(renderExpressionForStringify($0.value))"
            }.joined(separator: ", ")
            return "[\(rendered)]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(renderExpressionForStringify(condition)) ? \(renderExpressionForStringify(trueExpression)) : \(renderExpressionForStringify(falseExpression))"
        case .unary(let operatorSymbol, let expression):
            return "\(operatorSymbol.rawValue)\(renderExpressionForStringify(expression))"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return
                "\(renderExpressionForStringify(lhs)) \(operatorSymbol.rawValue) \(renderExpressionForStringify(rhs))"
        }
    }

    static func renderArgumentsForStringify(_ arguments: [CallArgument]) -> String {
        arguments.map { argument in
            let renderedValue = renderExpressionForStringify(argument.value)
            if let label = argument.label {
                return "\(label): \(renderedValue)"
            }
            return renderedValue
        }.joined(separator: ", ")
    }
}
