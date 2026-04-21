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

enum StateTransformHook {
    case initializer
    case getter
    case setter
}

struct StateTransformRegistration {
    let hook: StateTransformHook
    let parameterName: String
    let body: Expression
}

struct StateMacroEffects {
    let type: TypeReference
    let initializerTransforms: [Expression]
    let getterTransforms: [Expression]
    let setterTransforms: [Expression]
}
