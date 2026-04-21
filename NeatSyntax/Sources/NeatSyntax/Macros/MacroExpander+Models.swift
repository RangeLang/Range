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
