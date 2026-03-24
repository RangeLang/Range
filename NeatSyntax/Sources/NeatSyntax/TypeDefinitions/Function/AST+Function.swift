import Foundation

public struct NeatFunctionParameter {
    public let localName: String
    public let externalLabel: String?
    public let typeName: String?
    public let slotName: String?

    public var name: String {
        localName
    }

    public var isOptional: Bool {
        guard let typeName else { return false }
        return typeName.hasSuffix("?")
    }
}

public struct CallableDeclaration {
    public let targetName: String?
    public let name: String
    public let hasExplicitParameterClause: Bool
    public let parameters: [NeatFunctionParameter]
    public let returnTypeName: String?
    public let body: [Statement]?
}

public struct InitializerDeclaration {
    public let parameters: [NeatFunctionParameter]
    public let body: [Statement]?
}
