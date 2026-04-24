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
    let context: MacroExpansionContext

    func emittedSyntaxKinds(of expression: Expression) -> Set<EmittedSyntaxKind> {
        switch expression {
        case .identifier(let path):
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
        default:
            return [.expression]
        }
    }

    func render(_ expression: Expression) -> Expression {
        switch expression {
        case .identifier(let path):
            return renderedTargetPath(path) ?? expression
        default:
            return expression
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
}
