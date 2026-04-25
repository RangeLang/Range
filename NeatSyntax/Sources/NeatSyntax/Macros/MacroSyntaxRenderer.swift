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
        case .object(let typeName, _) where typeName == "NamedTypeReference" || typeName == "MemberTypeReference":
            return renderNominalTypeReference(value)
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
            default:
                return nil
            }
        default:
            return nil
        }
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
            let nameValue = fields["name"],
            let caseName = renderString(nameValue)
        else {
            guard let expression = value.expression else {
                return ""
            }
            return renderExpressionForSyntax(expression)
        }

        return "case \(caseName)"
    }

    private func renderEnumCase(_ expression: Expression) -> String {
        guard case .call(let name, let arguments) = expression,
            name == "Enum.Case",
            let nameExpression = argument("name", in: arguments),
            let caseName = renderString(nameExpression)
        else {
            return renderExpressionForSyntax(expression)
        }

        return "case \(caseName)"
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
        default:
            return MacroExpander.renderExpressionForStringify(expression)
        }
    }
}

