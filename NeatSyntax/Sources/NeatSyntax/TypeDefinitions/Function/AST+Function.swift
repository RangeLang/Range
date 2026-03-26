import Foundation

public struct NeatFunctionParameter {
    public let macros: [MacroApplication]
    public let localName: String
    public let externalLabel: String?
    public let typeReference: TypeReference?
    public let slotName: String?

    public var name: String {
        localName
    }

    public var isOptional: Bool {
        guard case .optional = typeReference else { return false }
        return true
    }
}

public struct CallableDeclaration {
    public let macros: [MacroApplication]
    public let targetType: TypeReference?
    public let name: String
    public let hasExplicitParameterClause: Bool
    public let parameters: [NeatFunctionParameter]
    public let returnType: TypeReference?
    public let body: [Statement]?
}

public struct InitializerDeclaration {
    public let macros: [MacroApplication]
    public let parameters: [NeatFunctionParameter]
    public let body: [Statement]?
}
