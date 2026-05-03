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
        case .integer(let value):
            return .integer(value)
        case .double(let value):
            return .double(value)
        case .boolean(let value):
            return .boolean(value)
        case .identifier(let path):
            if let bound = locals[path] {
                return evaluate(bound, locals: locals)
            }
            if path.hasPrefix(".") {
                return enumCaseValue(named: String(path.dropFirst()))
            }
            return evaluatePath(path, locals: locals)
        case .array(let elements):
            let values = elements.compactMap { evaluate($0, locals: locals) }
            guard values.count == elements.count else {
                return nil
            }
            return .array(values)
        case .call(let name, let arguments):
            if let syntaxValue = evaluateSyntaxHelper(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return syntaxValue
            }
            if let stringValue = evaluateStringTransform(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return stringValue
            }
            if let transformed = evaluateArrayTransform(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return transformed
            }
            if let element = evaluateArrayElementAccess(
                name: name,
                arguments: arguments,
                locals: locals
            ) {
                return element
            }
            return evaluateObjectConstruction(name: name, arguments: arguments, locals: locals)
        case .ternary(let condition, let trueExpression, let falseExpression):
            guard case .boolean(let conditionValue) = evaluate(condition, locals: locals) else {
                return nil
            }
            return evaluate(conditionValue ? trueExpression : falseExpression, locals: locals)
        case .binary(let lhs, .addition, let rhs):
            guard case .string(let left) = evaluate(lhs, locals: locals),
                case .string(let right) = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .string(left + right)
        case .binary(let lhs, .equal, let rhs):
            guard let left = evaluate(lhs, locals: locals),
                let right = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .boolean(valuesEqual(left, right))
        case .binary(let lhs, .notEqual, let rhs):
            guard let left = evaluate(lhs, locals: locals),
                let right = evaluate(rhs, locals: locals)
            else {
                return nil
            }
            return .boolean(!valuesEqual(left, right))
        default:
            return nil
        }
    }

    private func enumCaseValue(named name: String) -> CompileTimeValue {
        .object(
            typeName: "Enum.Case",
            fields: [
                "name": .string(name),
                "associatedValues": .array([]),
            ]
        )
    }

    private func valuesEqual(_ lhs: CompileTimeValue, _ rhs: CompileTimeValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let left), .string(let right)):
            return left == right
        case (.integer(let left), .integer(let right)):
            return left == right
        case (.double(let left), .double(let right)):
            return left == right
        case (.boolean(let left), .boolean(let right)):
            return left == right
        case (.object("Enum.Case", let left), .object("Enum.Case", let right)):
            guard case .string(let leftName)? = left["name"],
                case .string(let rightName)? = right["name"]
            else {
                return false
            }
            return leftName == rightName
        default:
            return false
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
            "Construct.Declaration", "Extension", "Macro.Application", "Marker.Application",
            "Block", "Switch", "SwitchCase", "Return", "Break", "Assignment",
            "ExpressionStatement":
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

    private func evaluateSyntaxHelper(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard name == "stringLiteralSyntax",
            arguments.count == 1,
            arguments[0].label == nil,
            case .string(let value) = evaluate(arguments[0].value, locals: locals)
        else {
            return nil
        }

        return .string("\"\(value)\"")
    }

    private func evaluateStringTransform(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        guard name.hasSuffix(".snakeCase"),
            arguments.isEmpty,
            let source = evaluatePath(String(name.dropLast(".snakeCase".count)), locals: locals),
            case .string(let value) = source
        else {
            return nil
        }
        return .string(snakeCase(value))
    }

    private func snakeCase(_ name: String) -> String {
        var result = ""
        var previousWasLowercaseOrDigit = false

        for scalar in name.unicodeScalars {
            let character = Character(scalar)
            let string = String(character)
            let isUppercase = string.uppercased() == string && string.lowercased() != string
            let isLowercase = string.lowercased() == string && string.uppercased() != string
            let isDigit = CharacterSet.decimalDigits.contains(scalar)

            if isUppercase && previousWasLowercaseOrDigit && !result.isEmpty {
                result.append("_")
            }

            result.append(string.lowercased())
            previousWasLowercaseOrDigit = isLowercase || isDigit
        }

        return result
    }

    private func evaluateArrayElementAccess(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let suffix = ".first"
        guard name.hasSuffix(suffix),
            let source = evaluatePath(String(name.dropLast(suffix.count)), locals: locals),
            case .array(let elements) = source
        else {
            return nil
        }

        if let first = elements.first {
            return first
        }

        guard let defaultExpression = argument("default", in: arguments) else {
            return nil
        }
        return evaluate(defaultExpression, locals: locals)
    }

    private func evaluateArrayTransform(
        name: String,
        arguments: [CallArgument],
        locals: [String: Expression]
    ) -> CompileTimeValue? {
        let supportedSuffixes = [".map", ".compactMap", ".flatMap", ".filter"]
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
        case ".filter":
            var filtered: [CompileTimeValue] = []
            for (element, value) in zip(elements, transformed) {
                guard case .boolean(let include) = value else {
                    return nil
                }
                if include {
                    filtered.append(element)
                }
            }
            return .array(filtered)
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

        for statement in body {
            switch statement {
            case .localBinding(let declaration):
                nestedLocals[declaration.name] = declaration.expression
            case .expression(let expression):
                return evaluate(expression, locals: nestedLocals)
            case .return(let expression?):
                return evaluate(expression, locals: nestedLocals)
            default:
                return nil
            }
        }

        return nil
    }

    private func argument(_ label: String, in arguments: [CallArgument]) -> Expression? {
        arguments.first(where: { $0.label == label })?.value
    }
}
