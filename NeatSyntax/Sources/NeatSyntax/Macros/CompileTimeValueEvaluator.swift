import Foundation

struct CompileTimeValueEvaluator {
    let targetBinding: String
    let targetValue: CompileTimeValue
    let localBindings: [String: Expression]

    func evaluate(_ expression: Expression) -> CompileTimeValue? {
        evaluate(expression, locals: localBindings)
    }

    private func evaluate(
        _ expression: Expression,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        switch expression {
        case .string(let value):
            return .string(value)
        case .identifier(let path):
            if let bound = locals[path] {
                return evaluate(bound, locals: locals)
            }
            return evaluatePath(path, locals: locals)
        case .array(let elements):
            let values = elements.compactMap { evaluate($0, locals: locals) }
            guard values.count == elements.count else {
                return nil
            }
            return .array(values)
        case .call(let name, let arguments):
            if let transformed = evaluateArrayTransform(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return transformed
            }
            return evaluateObjectConstruction(name: name, arguments: arguments, locals: locals)
        default:
            return nil
        }
    }

    private func evaluatePath(_ path: String, locals: [String: Expression]) -> CompileTimeValue? {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else {
            return nil
        }

        let root = components[0]
        let value: CompileTimeValue?
        if root == targetBinding {
            value = targetValue
        } else if let local = locals[root] {
            value = evaluate(local, locals: locals)
        } else {
            value = nil
        }

        guard var current = value else {
            return nil
        }

        for component in components.dropFirst() {
            guard let next = current.field(component) else {
                return nil
            }
            current = next
        }

        return current
    }

    private func evaluateObjectConstruction(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        switch name {
        case "Enum", "Enum.Declaration", "Enum.Case", "NamedTypeReference", "MemberTypeReference",
            "Let", "State", "Binding", "Derived", "Init.Declaration", "Function.Declaration",
            "Construct.Declaration", "Extension":
            var fields: [String: CompileTimeValue] = [:]
            for argument in arguments {
                guard let label = argument.label,
                    let value = evaluate(argument.value, locals: locals)
                else {
                    return nil
                }
                fields[label] = value
            }
            return .object(typeName: name, fields: fields)
        default:
            return nil
        }
    }

    private func evaluateArrayTransform(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let supportedSuffixes = [".map", ".compactMap", ".flatMap"]
        guard let suffix = supportedSuffixes.first(where: { name.hasSuffix($0) }),
            arguments.count == 1,
            arguments[0].label == nil,
            case .call("Closure", let closureArguments) = arguments[0].value,
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .array(let elements) = source
        else {
            return nil
        }

        let transformed = elements.compactMap { element -> CompileTimeValue? in
            evaluateSingleParameterClosure(
                closureArguments,
                element: element,
                locals: locals
            )
        }

        switch suffix {
        case ".map":
            guard transformed.count == elements.count else {
                return nil
            }
            return .array(transformed)
        case ".compactMap":
            return .array(transformed)
        case ".flatMap":
            var flattened: [CompileTimeValue] = []
            for value in transformed {
                guard case .array(let nested) = value else {
                    return nil
                }
                flattened.append(contentsOf: nested)
            }
            return .array(flattened)
        default:
            return nil
        }
    }

    private func evaluateSingleParameterClosure(
        _ closureArguments: [CallArgument],
        element: CompileTimeValue,
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard let parameterExpression = argument("parameters", in: closureArguments),
            case .array(let parameterExpressions) = parameterExpression,
            parameterExpressions.count == 1,
            case .identifier(let parameterName) = parameterExpressions[0],
            let bodyExpression = argument("body", in: closureArguments),
            case .block(let body) = bodyExpression
        else {
            return nil
        }

        var nestedLocals = locals
        nestedLocals[parameterName] = element.expression

        guard body.count == 1 else {
            return nil
        }

        switch body[0] {
        case .expression(let expression):
            return evaluate(expression, locals: nestedLocals)
        case .return(let expression?):
            return evaluate(expression, locals: nestedLocals)
        default:
            return nil
        }
    }

    private func argument(_ label: String, in arguments: [CallArgument]) -> Expression? {
        arguments.first(where: { $0.label == label })?.value
    }
}

