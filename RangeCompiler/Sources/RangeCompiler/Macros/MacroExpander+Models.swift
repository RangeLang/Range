import Foundation

struct MacroTargetSurface {
    let targetBinding: String
    let graphBinding: String?
    let selfValue: CompileTimeValue?
    let targetType: TypeReference
    let targetDeclarationName: String
    let localBindings: [String: Expression]
    let targetValue: CompileTimeValue
    let context: MacroExpansionContext

    private var evaluator: CompileTimeValueEvaluator {
        CompileTimeValueEvaluator(
            targetBinding: targetBinding,
            targetValue: targetValue,
            graphBinding: graphBinding,
            selfValue: selfValue,
            localBindings: localBindings,
            macroDeclarationsByName: context.macroDeclarationsByName,
            context: context
        )
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

    private func isTargetPath(_ path: String) -> Bool {
        path == targetBinding || path.hasPrefix("\(targetBinding).")
    }

    func renderedTargetPath(_ path: String) -> Expression? {
        guard isTargetPath(path) else {
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
