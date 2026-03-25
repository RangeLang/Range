import Foundation

public struct MacroDeclaration {
    public let name: String
    public let genericParameters: [String]
    public let parameters: [NeatFunctionParameter]
    public let target: MacroTarget
    public let bindings: MacroBindings
    public let body: [Statement]
}

public enum MacroTarget {
    case attached(String)
    case freestanding(String)
}

public struct MacroBindings {
    public let target: String
    public let result: String
    public let diagnostics: String
}
