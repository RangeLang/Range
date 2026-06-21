import Foundation

struct MacroSyntaxRenderer {
    let localBindings: [String: Expression]
    let renderedTargetPath: (String) -> Expression?

    func renderSyntax(_ value: CompileTimeValue) -> String? {
        switch value {
        case .object(let typeName, let fields) where typeName == "Enum":
            guard let declaration = fields["declaration"] else {
                return nil
            }
            return renderEnum(declaration)
        case .object(let typeName, _) where typeName == "Enum.Declaration":
            return renderEnum(value)
        case .object(let typeName, _) where typeName == "Block":
            return renderBlock(value)
        case .object(let typeName, _) where typeName == "Switch" || typeName == "If" || typeName == "Return"
            || typeName == "Break" || typeName == "Assignment"
            || typeName == "ExpressionStatement":
            return renderStatement(value)
        case .object(let typeName, _) where typeName == "Identifier":
            return renderIdentifier(value)
        case .object(let typeName, _) where typeName == "ArrayExpression"
            || typeName == "EnumCaseExpression":
            return renderExpressionForSyntax(value)
        case .object(let typeName, _) where typeName == "NamedTypeReference" || typeName == "MemberTypeReference":
            return renderNominalTypeReference(value)
        case .object(let typeName, _) where typeName == "Let" || typeName == "State"
            || typeName == "Binding" || typeName == "Derived"
            || typeName == "Function.Declaration" || typeName == "Construct.Declaration":
            return renderDeclaration(value)
        case .array(let values):
            let rendered = values.compactMap(renderSyntax)
            guard rendered.count == values.count else {
                return nil
            }
            return rendered.joined(separator: "\n")
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    func renderSyntax(_ expression: Expression) -> String? {
        switch expression {
        case .identifier(let path):
            if let bound = localBindings[path] {
                return renderSyntax(bound)
            }
            if let rendered = renderedTargetPath(path) {
                return renderExpressionForSyntax(rendered)
            }
            return nil
        case .call(let name, let arguments):
            switch name {
            case "Enum":
                guard let declaration = argument("declaration", in: arguments) else {
                    return nil
                }
                return renderEnum(declaration)
            case "Enum.Declaration":
                return renderEnum(expression)
            case "Block":
                return renderBlock(expression)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func renderDeclaration(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value else {
            return nil
        }

        switch typeName {
        case "Let":
            return renderProperty(keyword: "@let", fields: fields)
        case "State":
            return renderProperty(keyword: "state", fields: fields)
        case "Binding":
            return renderProperty(keyword: "binding", fields: fields)
        case "Derived":
            return renderProperty(keyword: "derived", fields: fields)
        case "Function.Declaration":
            return renderFunctionDeclaration(fields)
        case "Construct.Declaration":
            return renderConstructDeclaration(fields)
        default:
            return nil
        }
    }

    private func renderProperty(keyword: String, fields: [String: CompileTimeValue]) -> String? {
        guard let name = renderIdentifierField(fields),
            let typeValue = fields["type"],
            let typeName = renderNominalTypeReference(typeValue)
        else {
            return nil
        }
        return "\(keyword) \(name): \(typeName)"
    }

    private func renderFunctionDeclaration(_ fields: [String: CompileTimeValue]) -> String? {
        guard let name = renderIdentifierField(fields) else {
            return nil
        }
        let generics = renderGenerics(fields["generics"]) ?? ""
        let parameters = renderParameters(fields["parameters"]) ?? ""
        let returnType = fields["returnType"].flatMap(renderNominalTypeReference) ?? "Void"
        let suffix = returnType == "Void" ? "" : ": \(returnType)"
        return "function \(name)\(generics)(\(parameters))\(suffix)"
    }

    private func renderConstructDeclaration(_ fields: [String: CompileTimeValue]) -> String? {
        guard let nameValue = fields["self"] ?? fields["identifier"],
            let name = renderNominalTypeReference(nameValue) ?? renderIdentifier(nameValue)
        else {
            return nil
        }
        let generics = renderGenerics(fields["generics"]) ?? ""
        let bodyValues = [
            fields["lets"],
            fields["states"],
            fields["bindings"],
            fields["deriveds"],
            fields["functions"],
            fields["constructs"],
            fields["extensions"],
        ]
        let body = bodyValues.compactMap { $0.flatMap(renderSyntax) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return body.isEmpty
            ? "construct \(name)\(generics) {}"
            : "construct \(name)\(generics) {\n\(body)\n}"
    }

    private func renderGenerics(_ value: CompileTimeValue?) -> String? {
        guard let value else {
            return ""
        }
        guard case .array(let elements) = value else {
            return nil
        }
        let rendered = elements.compactMap(renderGeneric)
        guard rendered.count == elements.count else {
            return nil
        }
        return rendered.isEmpty ? "" : "<\(rendered.joined(separator: ", "))>"
    }

    private func renderGeneric(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value,
            typeName == "TypeGeneric" || typeName == "ValueGeneric",
            let name = renderIdentifierField(fields)
        else {
            return nil
        }
        if typeName == "TypeGeneric" {
            return name
        }
        guard let type = fields["type"].flatMap(renderNominalTypeReference) else {
            return nil
        }
        return "\(name): \(type)"
    }

    private func renderParameters(_ value: CompileTimeValue?) -> String? {
        guard let value else {
            return ""
        }
        guard case .array(let elements) = value else {
            return nil
        }
        let rendered = elements.compactMap(renderParameter)
        guard rendered.count == elements.count else {
            return nil
        }
        return rendered.joined(separator: ", ")
    }

    private func renderParameter(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value,
            typeName == "Parameter.Declaration",
            let name = renderIdentifierField(fields),
            let type = fields["type"].flatMap(renderNominalTypeReference)
        else {
            return nil
        }
        return "\(name): \(type)"
    }

    private func renderEnum(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value,
            typeName == "Enum.Declaration",
            let selfValue = fields["self"],
            let enumName = renderNominalTypeReference(selfValue),
            let casesValue = fields["cases"],
            let cases = renderEnumCases(casesValue)
        else {
            return nil
        }

        let body = cases.isEmpty ? "" : " \(cases.joined(separator: " ")) "
        return "enum \(enumName) {\(body)}"
    }

    private func renderEnum(_ expression: Expression) -> String? {
        guard case .call(let name, let arguments) = expression,
            name == "Enum.Declaration"
        else {
            return nil
        }
        guard
            let selfExpression = argument("self", in: arguments),
            let enumName = renderNominalTypeReference(selfExpression),
            let casesExpression = argument("cases", in: arguments),
            let cases = renderEnumCases(casesExpression)
        else {
            return nil
        }
        let body = cases.isEmpty ? "" : " \(cases.joined(separator: " ")) "
        return "enum \(enumName) {\(body)}"
    }

    private func renderEnumCases(_ value: CompileTimeValue) -> [String]? {
        guard case .array(let elements) = value else {
            return nil
        }
        return elements.map(renderEnumCase)
    }

    private func renderEnumCases(_ expression: Expression) -> [String]? {
        guard case .array(let elements) = expression else {
            return nil
        }
        return elements.map(renderEnumCase)
    }

    private func renderEnumCase(_ value: CompileTimeValue) -> String {
        guard case .object(let typeName, let fields) = value,
            typeName == "Enum.Case",
            let caseName = renderIdentifierField(fields)
        else {
            guard let expression = value.expression else {
                return ""
            }
            return renderExpressionForSyntax(expression)
        }

        let associatedValues = renderAssociatedValueClause(fields["associatedValues"]) ?? ""
        return "case \(caseName)\(associatedValues)"
    }

    private func renderEnumCase(_ expression: Expression) -> String {
        guard case .call(let name, let arguments) = expression,
            name == "Enum.Case",
            let caseName = renderIdentifierArgument(arguments)
        else {
            return renderExpressionForSyntax(expression)
        }

        let associatedValues = renderAssociatedValueClause(argument("associatedValues", in: arguments)) ?? ""
        return "case \(caseName)\(associatedValues)"
    }

    private func renderAssociatedValueClause(_ value: CompileTimeValue?) -> String? {
        guard let value else { return "" }
        guard case .array(let elements) = value else {
            return nil
        }
        let rendered = elements.compactMap(renderAssociatedValue)
        guard rendered.count == elements.count else {
            return nil
        }
        return rendered.isEmpty ? "" : "(\(rendered.joined(separator: ", ")))"
    }

    private func renderAssociatedValueClause(_ expression: Expression?) -> String? {
        guard let expression else { return "" }
        guard case .array(let elements) = expression else {
            return nil
        }
        let rendered = elements.compactMap(renderAssociatedValue)
        guard rendered.count == elements.count else {
            return nil
        }
        return rendered.isEmpty ? "" : "(\(rendered.joined(separator: ", ")))"
    }

    private func renderAssociatedValue(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value,
            typeName == "Enum.AssociatedValue",
            let typeValue = fields["type"],
            let typeName = renderNominalTypeReference(typeValue)
        else {
            return nil
        }
        let label = (fields["label"] ?? fields["name"]).flatMap(renderString)
        if let label, !label.isEmpty {
            return "\(label): \(typeName)"
        }
        return typeName
    }

    private func renderAssociatedValue(_ expression: Expression) -> String? {
        guard case .call(let name, let arguments) = expression,
            name == "Enum.AssociatedValue",
            let typeExpression = argument("type", in: arguments),
            let typeName = renderNominalTypeReference(typeExpression)
        else {
            return nil
        }
        let label = (argument("label", in: arguments) ?? argument("name", in: arguments))
            .flatMap(renderString)
        if let label, !label.isEmpty {
            return "\(label): \(typeName)"
        }
        return typeName
    }

    private func renderBlock(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value,
            typeName == "Block",
            let statementsValue = fields["statements"],
            case .array(let statements) = statementsValue
        else {
            return nil
        }

        return statements.compactMap(renderStatement).joined(separator: "\n")
    }

    private func renderBlock(_ expression: Expression) -> String? {
        guard case .call(let name, let arguments) = expression,
            name == "Block",
            let statementsExpression = argument("statements", in: arguments),
            case .array(let statements) = statementsExpression
        else {
            return nil
        }

        return statements.compactMap(renderStatement).joined(separator: "\n")
    }

    private func renderStatement(_ value: CompileTimeValue) -> String? {
        switch value {
        case .object(let typeName, let fields) where typeName == "Switch":
            guard let expression = fields["expression"],
                let casesValue = fields["cases"],
                case .array(let cases) = casesValue
            else {
                return nil
            }
            let renderedCases = cases.compactMap(renderSwitchCase)
            guard renderedCases.count == cases.count else {
                return nil
            }
            return "switch \(renderExpressionForSyntax(expression)) { \(renderedCases.joined(separator: " ")) }"
        case .object(let typeName, let fields) where typeName == "If":
            guard let condition = fields["condition"],
                let thenBody = fields["thenBody"],
                let renderedThenBody = renderBlock(thenBody)
            else {
                return nil
            }
            let renderedElse = fields["elseBody"].flatMap(renderBlock).map { " else { \($0) }" } ?? ""
            return "if \(renderExpressionForSyntax(condition)) { \(renderedThenBody) }\(renderedElse)"
        case .object(let typeName, let fields) where typeName == "Return":
            guard let expression = fields["expression"] else {
                return "return"
            }
            return "return \(renderExpressionForSyntax(expression))"
        case .object(let typeName, _) where typeName == "Break":
            return "break"
        case .object(let typeName, let fields) where typeName == "Assignment":
            guard let target = fields["target"],
                let expression = fields["expression"]
            else {
                return nil
            }
            return "state \(renderExpressionForSyntax(target)): \(renderExpressionForSyntax(expression))"
        case .object(let typeName, let fields) where typeName == "ExpressionStatement":
            guard let expression = fields["expression"] else {
                return nil
            }
            return renderExpressionForSyntax(expression)
        case .string(let expression):
            return expression
        default:
            guard let expression = value.expression else {
                return nil
            }
            return renderExpressionForSyntax(expression)
        }
    }

    private func renderStatement(_ expression: Expression) -> String? {
        switch expression {
        case .call(let name, let arguments) where name == "Switch":
            guard let switchExpression = argument("expression", in: arguments),
                let casesExpression = argument("cases", in: arguments),
                case .array(let cases) = casesExpression
            else {
                return nil
            }
            let renderedCases = cases.compactMap(renderSwitchCase)
            guard renderedCases.count == cases.count else {
                return nil
            }
            return "switch \(renderExpressionForSyntax(switchExpression)) { \(renderedCases.joined(separator: " ")) }"
        case .call(let name, let arguments) where name == "If":
            guard let condition = argument("condition", in: arguments),
                let thenBody = argument("thenBody", in: arguments),
                let renderedThenBody = renderBlock(thenBody)
            else {
                return nil
            }
            let renderedElse = argument("elseBody", in: arguments)
                .flatMap(renderBlock)
                .map { " else { \($0) }" } ?? ""
            return "if \(renderExpressionForSyntax(condition)) { \(renderedThenBody) }\(renderedElse)"
        case .call(let name, let arguments) where name == "Return":
            guard let returnExpression = argument("expression", in: arguments) else {
                return "return"
            }
            return "return \(renderExpressionForSyntax(returnExpression))"
        case .call(let name, _) where name == "Break":
            return "break"
        case .call(let name, let arguments) where name == "Assignment":
            guard let target = argument("target", in: arguments),
                let assignmentExpression = argument("expression", in: arguments)
            else {
                return nil
            }
            return "state \(renderExpressionForSyntax(target)): \(renderExpressionForSyntax(assignmentExpression))"
        case .call(let name, let arguments) where name == "ExpressionStatement":
            guard let statementExpression = argument("expression", in: arguments) else {
                return nil
            }
            return renderExpressionForSyntax(statementExpression)
        default:
            return renderExpressionForSyntax(expression)
        }
    }

    private func renderSwitchCase(_ value: CompileTimeValue) -> String? {
        guard case .object(let typeName, let fields) = value,
            typeName == "SwitchCase",
            let pattern = fields["pattern"],
            let body = fields["body"],
            let renderedBody = renderBlock(body)
        else {
            return nil
        }

        return "case \(renderExpressionForSyntax(pattern)): \(renderedBody)"
    }

    private func renderSwitchCase(_ expression: Expression) -> String? {
        guard case .call(let name, let arguments) = expression,
            name == "SwitchCase",
            let pattern = argument("pattern", in: arguments),
            let body = argument("body", in: arguments),
            let renderedBody = renderBlock(body)
        else {
            return nil
        }

        return "case \(renderExpressionForSyntax(pattern)): \(renderedBody)"
    }

    private func renderNominalTypeReference(_ value: CompileTimeValue) -> String? {
        switch value {
        case .object(let typeName, let fields) where typeName == "NamedTypeReference":
            guard let nameValue = fields["name"] else {
                return nil
            }
            return renderString(nameValue)
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    private func renderIdentifierField(_ fields: [String: CompileTimeValue]) -> String? {
        if let identifier = fields["identifier"] {
            return renderIdentifier(identifier)
        }
        if let name = fields["name"] {
            return renderString(name)
        }
        return nil
    }

    private func renderIdentifierArgument(_ arguments: [CallArgument]) -> String? {
        if let identifier = argument("identifier", in: arguments) {
            return renderIdentifier(identifier)
        }
        if let name = argument("name", in: arguments) {
            return renderString(name)
        }
        return nil
    }

    private func renderIdentifier(_ value: CompileTimeValue) -> String? {
        switch value {
        case .object(let typeName, let fields) where typeName == "Identifier":
            guard let name = fields["name"] else {
                return nil
            }
            return renderString(name)
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    private func renderIdentifier(_ expression: Expression) -> String? {
        switch expression {
        case .identifier(let path):
            if let bound = localBindings[path] {
                return renderIdentifier(bound)
            }
            if let rendered = renderedTargetPath(path) {
                return renderExpressionForSyntax(rendered)
            }
            return path
        case .string(let value):
            return value
        case .call(let name, let arguments) where name == "Identifier":
            guard let nameExpression = argument("name", in: arguments) else {
                return nil
            }
            return renderString(nameExpression)
        default:
            return nil
        }
    }

    private func renderNominalTypeReference(_ expression: Expression) -> String? {
        switch expression {
        case .identifier(let path):
            if let bound = localBindings[path] {
                return renderNominalTypeReference(bound)
            }
            if let rendered = renderedTargetPath(path) {
                return renderExpressionForSyntax(rendered)
            }
            return path
        case .string(let value):
            return value
        case .call(let name, let arguments) where name == "NamedTypeReference":
            guard let nameExpression = argument("name", in: arguments) else {
                return nil
            }
            return renderString(nameExpression)
        default:
            return nil
        }
    }

    private func renderString(_ expression: Expression) -> String? {
        switch expression {
        case .string(let value):
            return value
        case .identifier(let path):
            if let bound = localBindings[path] {
                return renderString(bound)
            }
            return nil
        default:
            return nil
        }
    }

    private func renderString(_ value: CompileTimeValue) -> String? {
        guard case .string(let value) = value else {
            return nil
        }
        return value
    }

    private func argument(_ label: String, in arguments: [CallArgument]) -> Expression? {
        arguments.first(where: { $0.label == label })?.value
    }

    private func renderExpressionForSyntax(_ expression: Expression) -> String {
        switch expression {
        case .identifier(let value):
            return value
        case .string(let value):
            return value
        case .call(let name, _) where name == "Identifier":
            return renderIdentifier(expression) ?? MacroExpander.renderExpressionForStringify(expression)
        default:
            return MacroExpander.renderExpressionForStringify(expression)
        }
    }

    private func renderExpressionForSyntax(_ value: CompileTimeValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .object(let typeName, _) where typeName == "Identifier":
            return renderIdentifier(value) ?? ""
        case .object(let typeName, let fields) where typeName == "ArrayExpression":
            guard let elementsValue = fields["elements"],
                case .array(let elements) = elementsValue
            else {
                return "[]"
            }
            return "[\(elements.map(renderExpressionForSyntax).joined(separator: ", "))]"
        case .object(let typeName, let fields) where typeName == "EnumCaseExpression":
            guard let identifierValue = fields["identifier"],
                let identifier = renderIdentifier(identifierValue)
            else {
                return "."
            }
            return ".\(identifier)"
        case .object(let typeName, let fields) where typeName == "WrittenExpression":
            guard case .object("WrittenSyntax", let writtenFields)? = fields["written"],
                case .string(let text)? = writtenFields["text"]
            else {
                return ""
            }
            return text
        default:
            guard let expression = value.expression else {
                return ""
            }
            return renderExpressionForSyntax(expression)
        }
    }
}
