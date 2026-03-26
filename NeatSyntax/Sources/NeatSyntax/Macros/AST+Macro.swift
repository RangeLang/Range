import Foundation

public struct MacroDeclaration {
    public let name: String
    public let genericParameters: [String]
    public let parameters: [NeatFunctionParameter]
    public let target: MacroTarget
    public let bindings: MacroBindings
    public let body: [Statement]
}

public struct MacroApplication {
    public let name: String
    public let argumentClause: String?
}

public enum MacroTarget {
    case attached(TypeReference)
    case freestanding(TypeReference)
}

public struct MacroBindings {
    public let target: String
    public let result: String
    public let diagnostics: String
}
