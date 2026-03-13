import Foundation
import NeatSyntax

struct JavaScriptGenerator {
    func generate(component: ComponentNode) -> String {
        let stateNames = Set(component.states.map(\.name))
        let stateLines = component.states.map(generateState).joined(separator: "\n")
        var renderButtonIndex = 0
        let renderMarkup = generateView(
            component.body,
            indentLevel: 2,
            buttonIndex: &renderButtonIndex,
            stateNames: stateNames
        )
        let debugLogs = generateDebugLogs(component.body)
        let handlers = generateHandlers(component.body, stateNames: stateNames)

        var sections: [String] = []
        sections.append(runtimePrelude())
        if !stateLines.isEmpty {
            sections.append(stateLines)
        }

        sections.append(
            """
            render(() => `
            \(renderMarkup)
            `);
            """
        )

        if !handlers.isEmpty {
            sections.append(handlers.joined(separator: "\n\n"))
        }
        if !debugLogs.isEmpty {
            sections.append(debugLogs.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func runtimePrelude() -> String {
        """
        const __neatHandlers = new Map();

        function state(initialValue) {
          let currentValue = initialValue;
          const read = () => currentValue;
          read.set = (nextValue) => {
            currentValue = nextValue;
          };
          return read;
        }

        function render(template) {
          return template();
        }

        function on(name, handler) {
          __neatHandlers.set(name, handler);
        }
        """
    }

    private func generateState(_ state: StateDeclaration) -> String {
        "const \(state.name) = state(\(generateExpression(state.initialValue, stateNames: [])));"
    }

    private func generateView(
        _ view: ViewNode,
        indentLevel: Int,
        buttonIndex: inout Int,
        stateNames: Set<String>
    ) -> String {
        let indent = String(repeating: "  ", count: indentLevel)

        switch view {
        case .text(let string):
            return
                "\(indent)<span>\(generateInterpolatedString(string, stateNames: stateNames))</span>"
        case .debugPrint:
            return ""
        case .button(let title, _):
            let handlerName = "button_\(buttonIndex)"
            buttonIndex += 1
            return "\(indent)<button data-click=\"\(handlerName)\">\(escapeLiteral(title))</button>"
        case .component(let name, let children):
            if let children {
                let nested = children.map {
                    generateView(
                        $0,
                        indentLevel: indentLevel + 1,
                        buttonIndex: &buttonIndex,
                        stateNames: stateNames
                    )
                }
                .joined(separator: "\n")
                return
                    "\(indent)<div data-neat-component=\"\(escapeLiteral(name))\">\n\(nested)\n\(indent)</div>"
            }
            return "\(indent)<div data-neat-component=\"\(escapeLiteral(name))\"></div>"
        case .element(let tag, let children):
            let nested = children.map {
                generateView(
                    $0,
                    indentLevel: indentLevel + 1,
                    buttonIndex: &buttonIndex,
                    stateNames: stateNames
                )
            }
            .joined(separator: "\n")
            if nested.isEmpty {
                return "\(indent)<\(tag)></\(tag)>"
            }
            return "\(indent)<\(tag)>\n\(nested)\n\(indent)</\(tag)>"
        case .slot:
            return ""
        case .vStack(let children):
            return generateVStack(
                children,
                indentLevel: indentLevel,
                buttonIndex: &buttonIndex,
                stateNames: stateNames
            )
        case .modified(let base, let modifiers):
            let baseMarkup = generateView(
                base,
                indentLevel: indentLevel,
                buttonIndex: &buttonIndex,
                stateNames: stateNames
            )
            return applyModifiers(baseMarkup: baseMarkup, modifiers: modifiers, indent: indent)
        }
    }

    private func generateVStack(
        _ children: [ViewNode],
        indentLevel: Int,
        buttonIndex: inout Int,
        stateNames: Set<String>
    )
        -> String
    {
        let indent = String(repeating: "  ", count: indentLevel)
        let innerIndentLevel = indentLevel + 1
        let childMarkup = children.map {
            generateView(
                $0,
                indentLevel: innerIndentLevel,
                buttonIndex: &buttonIndex,
                stateNames: stateNames
            )
        }
        .joined(separator: "\n")

        if childMarkup.isEmpty {
            return "\(indent)<div class=\"vstack\"></div>"
        }

        return """
            \(indent)<div class="vstack">
            \(childMarkup)
            \(indent)</div>
            """
    }

    private func generateInterpolatedString(
        _ string: InterpolatedString,
        stateNames: Set<String>,
        context: JSHandlerContext? = nil
    ) -> String {
        string.segments.map { segment in
            switch segment {
            case .text(let value):
                return escapeLiteral(value)
            case .expression(let expression):
                return
                    "${\(generateExpression(expression, stateNames: stateNames, context: context))}"
            }
        }.joined()
    }

    private func generateHandlers(_ root: ViewNode, stateNames: Set<String>) -> [String] {
        var handlers: [String] = []
        var buttonIndex = 0
        collectHandlers(
            view: root,
            buttonIndex: &buttonIndex,
            handlers: &handlers,
            stateNames: stateNames
        )
        return handlers
    }

    private func generateDebugLogs(_ root: ViewNode) -> [String] {
        var logs: [String] = []
        collectDebugLogs(view: root, logs: &logs)
        return logs
    }

    private func collectHandlers(
        view: ViewNode,
        buttonIndex: inout Int,
        handlers: inout [String],
        stateNames: Set<String>
    ) {
        switch view {
        case .text:
            return
        case .debugPrint:
            return
        case .button(_, let action):
            let handlerName = "button_\(buttonIndex)"
            buttonIndex += 1
            var context = JSHandlerContext()
            let body = action.map {
                generateStatement($0, stateNames: stateNames, context: &context)
            }
            .joined(separator: "\n")
            handlers.append(
                """
                on("\(handlerName)", () => {
                \(indent(body, level: 1))
                });
                """
            )
        case .component(_, let children):
            if let children {
                for child in children {
                    collectHandlers(
                        view: child,
                        buttonIndex: &buttonIndex,
                        handlers: &handlers,
                        stateNames: stateNames
                    )
                }
            }
            return
        case .element(_, let children):
            for child in children {
                collectHandlers(
                    view: child,
                    buttonIndex: &buttonIndex,
                    handlers: &handlers,
                    stateNames: stateNames
                )
            }
        case .slot:
            return
        case .vStack(let children):
            for child in children {
                collectHandlers(
                    view: child,
                    buttonIndex: &buttonIndex,
                    handlers: &handlers,
                    stateNames: stateNames
                )
            }
        case .modified(let base, _):
            collectHandlers(
                view: base,
                buttonIndex: &buttonIndex,
                handlers: &handlers,
                stateNames: stateNames
            )
        }
    }

    private func collectDebugLogs(view: ViewNode, logs: inout [String]) {
        switch view {
        case .text:
            return
        case .button:
            return
        case .component(_, let children):
            if let children {
                for child in children {
                    collectDebugLogs(view: child, logs: &logs)
                }
            }
            return
        case .element(_, let children):
            for child in children {
                collectDebugLogs(view: child, logs: &logs)
            }
        case .slot:
            return
        case .vStack(let children):
            for child in children {
                collectDebugLogs(view: child, logs: &logs)
            }
        case .debugPrint(let message):
            logs.append("console.log(`\(generateInterpolatedString(message, stateNames: []))`);")
        case .modified(let base, _):
            collectDebugLogs(view: base, logs: &logs)
        }
    }

    private func applyModifiers(baseMarkup: String, modifiers: [ModifierCall], indent: String)
        -> String
    {
        var current = baseMarkup
        var classes: [String] = []
        for modifier in modifiers {
            if modifier.name == "class",
                let argument = firstModifierArgumentValue(modifier),
                case .string(let className) = argument
            {
                classes.append(className)
                continue
            }
            guard let style = styleForModifier(modifier), !style.isEmpty else { continue }
            current = "\(indent)<div style=\"\(style)\">\n\(current)\n\(indent)</div>"
        }
        if !classes.isEmpty {
            current =
                "\(indent)<div class=\"\(classes.joined(separator: " "))\">\n\(current)\n\(indent)</div>"
        }
        return current
    }

    private func styleForModifier(_ modifier: ModifierCall) -> String? {
        switch modifier.name.lowercased() {
        case "background":
            guard let argument = colorArgumentValue(from: modifier) else { return nil }
            let color = colorValue(from: argument)
            return color.isEmpty ? nil : "background: \(color);"
        case "padding":
            guard let value = paddingValue(from: modifier) else { return nil }
            return "padding: \(value);"
        case "shadow", "shading":
            guard let value = shadowValue(from: modifier) else { return nil }
            return "box-shadow: \(value);"
        default:
            return nil
        }
    }

    private func firstModifierArgumentValue(_ modifier: ModifierCall) -> ModifierArgument? {
        modifier.arguments.first?.value
    }

    private func colorArgumentValue(from modifier: ModifierCall) -> ModifierArgument? {
        if let labeled = modifier.arguments.first(where: { $0.label == "color" }) {
            return labeled.value
        }
        return firstModifierArgumentValue(modifier)
    }

    private func labeledArgumentValue(_ label: String, from modifier: ModifierCall)
        -> ModifierArgument?
    {
        modifier.arguments.first(where: { $0.label == label })?.value
    }

    private func paddingValue(from modifier: ModifierCall) -> String? {
        var labeled: [String: ModifierArgument] = [:]
        for argument in modifier.arguments {
            guard let label = argument.label else { continue }
            labeled[label] = argument.value
        }

        if !labeled.isEmpty {
            let all = labeled["all"].flatMap(lengthToken)
            let horizontal = labeled["horizontal"].flatMap(lengthToken)
            let vertical = labeled["vertical"].flatMap(lengthToken)
            let top = labeled["top"].flatMap(lengthToken) ?? vertical ?? all
            let right = labeled["right"].flatMap(lengthToken) ?? horizontal ?? all
            let bottom = labeled["bottom"].flatMap(lengthToken) ?? vertical ?? all
            let left = labeled["left"].flatMap(lengthToken) ?? horizontal ?? all

            guard let top, let right, let bottom, let left else { return nil }
            return "\(top) \(right) \(bottom) \(left)"
        }

        let values = modifier.arguments.compactMap { lengthToken($0.value) }
        switch values.count {
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) \(values[1])"
        case 3:
            return "\(values[0]) \(values[1]) \(values[2])"
        case 4:
            return "\(values[0]) \(values[1]) \(values[2]) \(values[3])"
        default:
            return nil
        }
    }

    private func shadowValue(from modifier: ModifierCall) -> String? {
        let defaultColor = "rgba(15, 23, 42, 18%)"
        let x =
            labeledArgumentValue("x", from: modifier).flatMap(lengthToken)
            ?? modifier.arguments.first.flatMap { lengthToken($0.value) }
            ?? "0px"
        let y =
            labeledArgumentValue("y", from: modifier).flatMap(lengthToken)
            ?? modifier.arguments.dropFirst().first.flatMap { lengthToken($0.value) }
            ?? "8px"
        let blur =
            labeledArgumentValue("blur", from: modifier).flatMap(lengthToken)
            ?? modifier.arguments.dropFirst(2).first.flatMap { lengthToken($0.value) }
            ?? "24px"
        let spread =
            labeledArgumentValue("spread", from: modifier).flatMap(lengthToken)
            ?? modifier.arguments.dropFirst(3).first.flatMap { lengthToken($0.value) }
            ?? "0px"

        let color: String
        if let labeledColor = labeledArgumentValue("color", from: modifier) {
            color = colorValue(from: labeledColor)
        } else if modifier.arguments.count >= 4,
            modifier.arguments[3].label == nil,
            lengthToken(modifier.arguments[3].value) == nil
        {
            color = colorValue(from: modifier.arguments[3].value)
        } else if modifier.arguments.count >= 5, modifier.arguments[4].label == nil {
            color = colorValue(from: modifier.arguments[4].value)
        } else {
            color = defaultColor
        }

        let finalColor = color.isEmpty ? defaultColor : color
        return "\(x) \(y) \(blur) \(spread) \(finalColor)"
    }

    private func lengthToken(_ argument: ModifierArgument) -> String? {
        switch argument {
        case .integer(let value):
            return "\(value)px"
        case .double(let value):
            return "\(renderNumberLiteral(value))px"
        case .percentage(let value):
            return "\(renderNumberLiteral(value))%"
        case .string(let value):
            return value
        case .identifier(let value):
            return value
        case .enumCase, .enumCall:
            return nil
        }
    }

    private func colorValue(from argument: ModifierArgument) -> String {
        switch argument {
        case .enumCase(let name):
            switch name.lowercased() {
            case "red": return "#ef4444"
            case "blue": return "#3b82f6"
            case "green": return "#22c55e"
            case "orange": return "#f97316"
            case "yellow": return "#facc15"
            case "purple": return "#a855f7"
            case "pink": return "#ec4899"
            case "black": return "#000000"
            case "white": return "#ffffff"
            case "clear": return "transparent"
            default: return ""
            }
        case .enumCall(let name, let arguments):
            return renderColorFunction(name: name, arguments: arguments)
        case .string(let value):
            return value
        case .identifier(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return renderNumberLiteral(value)
        case .percentage(let value):
            return "\(renderNumberLiteral(value))%"
        }
    }

    private func renderColorFunction(name: String, arguments: [ModifierArgument]) -> String {
        let fn = name.lowercased()
        switch fn {
        case "rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch":
            let joined = arguments.map(colorArgumentToken).joined(separator: ", ")
            return "\(fn)(\(joined))"
        case "hex":
            guard let first = arguments.first else { return "" }
            let raw = colorArgumentToken(first).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return "" }
            return raw.hasPrefix("#") ? raw : "#\(raw)"
        default:
            return ""
        }
    }

    private func colorArgumentToken(_ argument: ModifierArgument) -> String {
        switch argument {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return renderNumberLiteral(value)
        case .percentage(let value):
            return "\(renderNumberLiteral(value))%"
        case .identifier(let value):
            return value
        case .enumCase(let value):
            return value
        case .enumCall(let name, let arguments):
            return renderColorFunction(name: name, arguments: arguments)
        }
    }

    private func renderNumberLiteral(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func generateStatement(
        _ statement: Statement,
        stateNames: Set<String>,
        context: inout JSHandlerContext
    ) -> String {
        switch statement {
        case .declaration(let kind, let name, let expression):
            let keyword: String
            switch kind {
            case .constant:
                keyword = "const"
            case .mutable:
                keyword = "let"
            }
            context.locals[name] = kind
            return
                "\(keyword) \(name) = \(generateExpression(expression, stateNames: stateNames, context: context));"
        case .assignment(let target, let expression):
            switch target {
            case .state(let name):
                return
                    "\(name).set(\(generateExpression(expression, stateNames: stateNames, context: context)));"
            case .local(let name):
                return
                    "\(name) = \(generateExpression(expression, stateNames: stateNames, context: context));"
            }
        case .compoundAssignment(let target, let operatorSymbol, let expression):
            switch operatorSymbol {
            case .plusEquals:
                switch target {
                case .state(let name):
                    return
                        "\(name).set(\(name)() + \(generateExpression(expression, stateNames: stateNames, context: context)));"
                case .local(let name):
                    return
                        "\(name) = \(name) + \(generateExpression(expression, stateNames: stateNames, context: context));"
                }
            }
        case .switchStatement(let expression, let cases, let defaultBody):
            return generateSwitchStatement(
                expression: expression,
                cases: cases,
                defaultBody: defaultBody,
                stateNames: stateNames,
                context: context
            )
        case .debugPrint(let message):
            return
                "console.log(`\(generateInterpolatedString(message, stateNames: stateNames, context: context))`);"
        }
    }

    private func generateSwitchStatement(
        expression: NeatSyntax.Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?,
        stateNames: Set<String>,
        context: JSHandlerContext
    ) -> String {
        let subject = generateExpression(expression, stateNames: stateNames, context: context)
        var lines: [String] = ["switch (\(subject)) {"]

        for caseNode in cases {
            let value = generateExpression(caseNode.value, stateNames: stateNames, context: context)
            var caseContext = context
            let statements = caseNode.body.map {
                generateStatement($0, stateNames: stateNames, context: &caseContext)
            }
            .joined(separator: "\n")
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
                generateStatement($0, stateNames: stateNames, context: &defaultContext)
            }
            .joined(separator: "\n")
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

    private func generateExpression(
        _ expression: NeatSyntax.Expression,
        stateNames: Set<String>,
        context: JSHandlerContext? = nil
    ) -> String {
        switch expression {
        case .integer(let value):
            return String(value)
        case .string(let value):
            return "\"\(escapeLiteral(value))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .identifier(let name):
            if context?.locals[name] != nil {
                return name
            }
            return stateNames.contains(name) ? "\(name)()" : name
        case .array(let values):
            let rendered = values.map {
                generateExpression($0, stateNames: stateNames, context: context)
            }.joined(separator: ", ")
            return "[\(rendered)]"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return
                "\(generateExpression(lhs, stateNames: stateNames, context: context)) \(operatorSymbol.rawValue) \(generateExpression(rhs, stateNames: stateNames, context: context))"
        }
    }

    private func escapeLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\"", with: "&quot;")
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

private struct JSHandlerContext {
    var locals: [String: LocalBindingKind] = [:]
}
