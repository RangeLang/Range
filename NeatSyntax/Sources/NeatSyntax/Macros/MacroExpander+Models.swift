import Foundation

enum ResolvedRewriteSite {
    case targetDirect
    case initApplication
    case functionApplication
    case functionArgumentExpression
    case parameterDeclarationType
    case parameterApplicationArguments
    case parameterApplicationArgument
}

struct ResolvedRewriteCall {
    let site: ResolvedRewriteSite
    let payload: Expression
}

struct ParameterApplicationRewritePlan {
    let payload: Expression
    let isVariadic: Bool
}

enum PropertyTransformHook {
    case initializer
    case getter
    case setter
}

enum PropertyDeclarationKind {
    case state
    case immutable
    case binding
    case derived
}

struct PropertyTransformRegistration {
    let hook: PropertyTransformHook
    let parameterName: String
    let body: Expression
}

struct PropertyMacroEffects {
    let kind: PropertyDeclarationKind
    let type: TypeReference
    let initializerTransforms: [Expression]
    let getterTransforms: [Expression]
    let setterTransforms: [Expression]
}

struct MacroTargetSurface {
    let targetBinding: String
    let targetType: TypeReference
    let targetDeclarationName: String
    let localBindings: [String: Expression]
    let targetValue: MacroValue
    let context: MacroExpansionContext

    private var evaluator: MacroValueEvaluator {
        MacroValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue,
            localBindings: localBindings
        )
    }

    func emittedSyntaxKinds(of expression: Expression) -> Set<EmittedSyntaxKind> {
        if let value = evaluator.evaluate(expression) {
            return emittedSyntaxKinds(of: value)
        }

        switch expression {
        case .identifier(let path):
            if let bound = localBindings[path] {
                return emittedSyntaxKinds(of: bound)
            }
            if let targetPathKinds = context.rewriteSurfaceView.emittedSyntaxKinds(
                forTargetPath: path,
                targetBinding: targetBinding,
                targetType: targetType
            ) {
                return targetPathKinds
            }
            if isTargetPath(path) {
                return [.expression]
            }
            return [.callableName, .declaration, .nominalTypeReference, .typeReference]
        case .string:
            return [.callableName, .declaration]
        case .call(let name, _):
            switch name {
            case "Enum":
                return [.declaration]
            case "NamedTypeReference", "MemberTypeReference":
                return [.nominalTypeReference, .typeReference]
            default:
                return [.expression]
            }
        default:
            return [.expression]
        }
    }

    func render(_ expression: Expression) -> Expression {
        if let value = evaluator.evaluate(expression),
            let expression = value.expression
        {
            return expression
        }

        switch expression {
        case .identifier(let path):
            if let bound = localBindings[path] {
                return render(bound)
            }
            return renderedTargetPath(path) ?? expression
        default:
            return expression
        }
    }

    func renderSyntax(_ expression: Expression) -> String? {
        if let value = evaluator.evaluate(expression) {
            return renderSyntax(value)
        }

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

    private func emittedSyntaxKinds(of value: MacroValue) -> Set<EmittedSyntaxKind> {
        switch value {
        case .string:
            return [.callableName, .declaration]
        case .array:
            return [.expression]
        case .object(let typeName, _):
            switch typeName {
            case "Enum":
                return [.declaration]
            case "NamedTypeReference", "MemberTypeReference":
                return [.nominalTypeReference, .typeReference]
            default:
                return [.expression]
            }
        }
    }

    private func isTargetPath(_ path: String) -> Bool {
        path == targetBinding || path.hasPrefix("\(targetBinding).")
    }

    private func renderedTargetPath(_ path: String) -> Expression? {
        guard isTargetPath(path) else {
            return nil
        }
        guard
            context.rewriteSurfaceView.emittedSyntaxKinds(
                forTargetPath: path,
                targetBinding: targetBinding,
                targetType: targetType
            ) != nil
        else {
            return nil
        }

        switch path {
        case "\(targetBinding).declaration.self":
            return .identifier(targetDeclarationName)
        default:
            return nil
        }
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

    private func renderSyntax(_ value: MacroValue) -> String? {
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

    private func renderEnum(_ value: MacroValue) -> String? {
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

    private func renderEnumCases(_ value: MacroValue) -> [String]? {
        guard case .array(let elements) = value else {
            return nil
        }
        return elements.map(renderEnumCase)
    }

    private func renderEnumCase(_ value: MacroValue) -> String {
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

    private func renderNominalTypeReference(_ value: MacroValue) -> String? {
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

    private func renderEnumCases(_ expression: Expression) -> [String]? {
        guard case .array(let elements) = expression else {
            return nil
        }
        return elements.map(renderEnumCase)
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

    private func renderString(_ value: MacroValue) -> String? {
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
