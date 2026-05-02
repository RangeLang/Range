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
    let targetValue: CompileTimeValue
    let context: MacroExpansionContext

    private var evaluator: CompileTimeValueEvaluator {
        CompileTimeValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue,
            localBindings: localBindings
        )
    }

    private var syntaxRenderer: MacroSyntaxRenderer {
        MacroSyntaxRenderer(
            localBindings: localBindings,
            renderedTargetPath: renderedTargetPath
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
            if let kinds = emittedSyntaxKinds(forConstructedTypeNamed: name) {
                return kinds
            }
            return [.expression]
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
            return syntaxRenderer.renderSyntax(value)
        }
        return syntaxRenderer.renderSyntax(expression)
    }

    private func emittedSyntaxKinds(of value: CompileTimeValue) -> Set<EmittedSyntaxKind> {
        switch value {
        case .string:
            return [.callableName, .declaration]
        case .integer, .double, .boolean, .array:
            return [.expression]
        case .object(let typeName, _) where typeName == "Block":
            return [.declaration]
        case .object(let typeName, _):
            if let kinds = emittedSyntaxKinds(forConstructedTypeNamed: typeName) {
                return kinds
            }
            return [.expression]
        }
    }

    private func emittedSyntaxKinds(forConstructedTypeNamed typeName: String) -> Set<EmittedSyntaxKind>? {
        context.rewriteSurfaceView.emittedSyntaxKinds(
            forSemanticType: TypeReference.named(typeName)
        )
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

}
