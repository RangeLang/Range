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

public enum EmittedDeclaration {
    case extensionDeclaration(EmittedExtensionDeclaration)
    case constructDeclaration(ConstructDeclaration)
    case callableDeclaration(CallableDeclaration)
    case namespaceDeclaration(NamespaceDeclaration)
    case enumDeclaration(EnumDeclaration)
    case protocolDeclaration(ProtocolDeclaration)
    case stateDeclaration(StateDeclaration)
}

public struct EmittedExtensionDeclaration {
    public let macros: [MacroApplication]
    public let target: EmittedNominalTypeReference
    public let conformances: [TypeReference]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]
}

public enum EmittedNominalTypeReference {
    case type(TypeReference)
    case splice(Expression)
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
