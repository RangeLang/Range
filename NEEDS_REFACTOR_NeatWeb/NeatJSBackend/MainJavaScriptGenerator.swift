import Foundation
import NeatSyntax

public struct MainJavaScriptGenerator {
    public init() {}

    public func generate(mainBlock: MainBlockNode) -> String {
        var context = JSMainContext()
        let lines = mainBlock.body.map {
            generateStatement(
                $0,
                stateNames: [],
                bindingNames: [],
                valueExpressions: [:],
                context: &context
            )
        }
        .joined(separator: "\n")

        return lines + "\n"
    }

    private func generateStatement(
        _ statement: Statement,
        stateNames: Set<String>,
        bindingNames: Set<String>,
        valueExpressions: [String: String],
        context: inout JSMainContext
    ) -> String {
        switch statement {
        case .declaration(let kind, let name, let expression):
            let keyword = kind == .constant ? "const" : "let"
            context.locals[name] = kind
            return
                "\(keyword) \(name) = \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context));"
        case .assignment(let target, let expression):
            switch target {
            case .state(let name):
                return
                    "\(name).set(\(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context)));"
            case .binding(let name):
                let targetName = valueExpressions[name] ?? name
                return
                    "\(targetName).value = \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context));"
            case .local(let name):
                return
                    "\(name) = \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context));"
            }
        case .compoundAssignment(let target, .plusEquals, let expression):
            switch target {
            case .state(let name):
                return
                    "\(name).set(\(name)() + \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context)));"
            case .binding(let name):
                let targetName = valueExpressions[name] ?? name
                return
                    "\(targetName).value = \(targetName).value + \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context));"
            case .local(let name):
                return
                    "\(name) = \(name) + \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context));"
            }
        case .forEach(let name, let sequence, let body):
            let sequenceValue = generateExpression(
                sequence,
                stateNames: stateNames,
                bindingNames: bindingNames,
                valueExpressions: valueExpressions,
                context: context
            )
            var loopContext = context
            loopContext.locals[name] = .constant
            let statements = body.map {
                generateStatement(
                    $0,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    context: &loopContext
                )
            }
            .joined(separator: "\n")
            return """
                for (const \(name) of (\(sequenceValue) ?? [])) {
                \(indent(statements, level: 1))
                }
                """
        case .whileLoop(let condition, let body):
            let renderedCondition = generateExpression(
                condition,
                stateNames: stateNames,
                bindingNames: bindingNames,
                valueExpressions: valueExpressions,
                context: context
            )
            var loopContext = context
            let statements = body.map {
                generateStatement(
                    $0,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    context: &loopContext
                )
            }
            .joined(separator: "\n")
            return """
                while (\(renderedCondition)) {
                \(indent(statements, level: 1))
                }
                """
        case .conditional(let branches):
            return generateConditionalStatement(
                branches: branches,
                stateNames: stateNames,
                bindingNames: bindingNames,
                valueExpressions: valueExpressions,
                context: context
            )
        case .return(let expression):
            if let expression {
                return
                    "return \(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context));"
            }
            return "return;"
        case .break:
            return "break;"
        case .continue:
            return "continue;"
        case .switchStatement(let expression, let cases, let defaultBody):
            return generateSwitchStatement(
                expression: expression,
                cases: cases,
                defaultBody: defaultBody,
                stateNames: stateNames,
                bindingNames: bindingNames,
                valueExpressions: valueExpressions,
                context: context
            )
        case .debugPrint(let message):
            return
                "console.log(`\(generateInterpolatedString(message, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context))`);"
        }
    }

    private func generateConditionalStatement(
        branches: [StatementConditionalBranch],
        stateNames: Set<String>,
        bindingNames: Set<String>,
        valueExpressions: [String: String],
        context: JSMainContext
    ) -> String {
        var lines: [String] = []
        for (index, branch) in branches.enumerated() {
            var branchContext = context
            let statements = branch.body.map {
                generateStatement(
                    $0,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    context: &branchContext
                )
            }.joined(separator: "\n")
            if let condition = branch.condition {
                let renderedCondition = generateExpression(
                    condition,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    context: context
                )
                lines.append("\(index == 0 ? "if" : "else if") (\(renderedCondition)) {")
            } else {
                lines.append("else {")
            }
            if !statements.isEmpty {
                lines.append(indent(statements, level: 1))
            }
            lines.append("}")
        }
        return lines.joined(separator: "\n")
    }

    private func generateSwitchStatement(
        expression: NeatSyntax.Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?,
        stateNames: Set<String>,
        bindingNames: Set<String>,
        valueExpressions: [String: String],
        context: JSMainContext
    ) -> String {
        let subject = generateExpression(
            expression,
            stateNames: stateNames,
            bindingNames: bindingNames,
            valueExpressions: valueExpressions,
            context: context
        )
        var lines: [String] = ["switch (\(subject)) {"]
        for caseNode in cases {
            let value = generateExpression(
                caseNode.value,
                stateNames: stateNames,
                bindingNames: bindingNames,
                valueExpressions: valueExpressions,
                context: context
            )
            var caseContext = context
            let statements = caseNode.body.map {
                generateStatement(
                    $0,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    context: &caseContext
                )
            }.joined(separator: "\n")
            lines.append("  case \(value): {")
            if !statements.isEmpty {
                lines.append(indent(statements, level: 2))
            }
            lines.append("    break;")
            lines.append("  }")
        }
        if let defaultBody {
            var defaultContext = context
            let statements = defaultBody.map {
                generateStatement(
                    $0,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    context: &defaultContext
                )
            }.joined(separator: "\n")
            lines.append("  default: {")
            if !statements.isEmpty {
                lines.append(indent(statements, level: 2))
            }
            lines.append("    break;")
            lines.append("  }")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func generateInterpolatedString(
        _ string: InterpolatedString,
        stateNames: Set<String>,
        bindingNames: Set<String>,
        valueExpressions: [String: String],
        context: JSMainContext? = nil
    ) -> String {
        string.segments.map { segment in
            switch segment {
            case .text(let value):
                return escapeLiteral(value)
            case .expression(let expression):
                return
                    "${\(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, context: context))}"
            }
        }.joined()
    }

    private func generateExpression(
        _ expression: NeatSyntax.Expression,
        stateNames: Set<String>,
        bindingNames: Set<String>,
        valueExpressions: [String: String] = [:],
        localBindings: Set<String> = [],
        context: JSMainContext? = nil
    ) -> String {
        switch expression {
        case .integer(let value):
            return String(value)
        case .string(let value):
            return "\"\(escapeLiteral(value))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .none:
            return "null"
        case .identifier(let name):
            if localBindings.contains(name) || context?.locals[name] != nil {
                return name
            }
            if let valueExpression = valueExpressions[name] {
                return bindingNames.contains(name) ? "\(valueExpression).value" : valueExpression
            }
            if bindingNames.contains(name) {
                return "\(name).value"
            }
            return stateNames.contains(name) ? "\(name)()" : name
        case .bindingReference(let name):
            return valueExpressions[name] ?? name
        case .array(let values):
            return
                "[\(values.map { generateExpression($0, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context) }.joined(separator: ", "))]"
        case .dictionary(let elements):
            return "{\(elements.map { element in
                let key = generateDictionaryKey(
                    element.key,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    localBindings: localBindings,
                    context: context
                )
                let value = generateExpression(
                    element.value,
                    stateNames: stateNames,
                    bindingNames: bindingNames,
                    valueExpressions: valueExpressions,
                    localBindings: localBindings,
                    context: context
                )
                return "\(key): \(value)"
            }.joined(separator: ", "))}"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "\(generateExpression(condition, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context)) ? \(generateExpression(trueExpression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context)) : \(generateExpression(falseExpression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context))"
        case .unary(let op, let nested):
            return
                "\(op.rawValue)\(generateExpression(nested, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context))"
        case .binary(let lhs, let op, let rhs):
            return
                "\(generateExpression(lhs, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context)) \(op.rawValue) \(generateExpression(rhs, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context))"
        }
    }

    private func escapeLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func generateDictionaryKey(
        _ expression: NeatSyntax.Expression,
        stateNames: Set<String>,
        bindingNames: Set<String>,
        valueExpressions: [String: String],
        localBindings: Set<String>,
        context: JSMainContext?
    ) -> String {
        switch expression {
        case .string(let value):
            return "\"\(escapeLiteral(value))\""
        case .identifier(let name):
            return name
        default:
            return "[\(generateExpression(expression, stateNames: stateNames, bindingNames: bindingNames, valueExpressions: valueExpressions, localBindings: localBindings, context: context))]"
        }
    }

    private func indent(_ value: String, level: Int) -> String {
        let prefix = String(repeating: "  ", count: level)
        return
            value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(prefix)\($0)" }
            .joined(separator: "\n")
    }
}

private struct JSMainContext {
    var locals: [String: LocalBindingKind] = [:]
}
