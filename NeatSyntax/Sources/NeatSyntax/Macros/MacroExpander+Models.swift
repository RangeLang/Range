import Foundation

struct AttachedParameterMacroSignature {
    let name: String
    let labels: [String?]
    let attachedParameterMacrosByIndex: [Int: MacroDeclaration]
}

struct AttachedFunctionMacroSignature {
    let name: String
    let labels: [String?]
    let attachedFunctionMacros: [MacroDeclaration]
}

enum MacroTargetKind: Equatable {
    case expression
    case block
    case parameter
    case initializer
    case function
    case other(String)
}

enum ResolvedRewriteSite {
    case targetDirect
    case initApplication
    case functionApplication
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
