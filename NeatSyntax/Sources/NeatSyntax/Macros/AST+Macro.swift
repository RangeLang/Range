import Foundation

public struct MacroDeclaration {
    public let name: String
    public let genericParameters: [GenericParameter]
    public let parameters: [NeatFunctionParameter]
    public let target: MacroTarget
    public let expansionType: TypeReference?
    public let bindings: MacroBindings
    public let body: [Statement]
}

public struct MacroApplication {
    public let name: String
    public let genericArguments: [TypeReference]
    public let argumentClause: String?
}

public enum MacroTarget {
    case syntax(TypeReference)

    public var typeReference: TypeReference {
        switch self {
        case .syntax(let typeReference):
            return typeReference
        }
    }
}

public struct MacroBindings {
    public let target: String
    public let diagnostics: String
}
