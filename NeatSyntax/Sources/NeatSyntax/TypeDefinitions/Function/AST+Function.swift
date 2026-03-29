import Foundation

public struct NeatFunctionParameter {
    public let macros: [MacroApplication]
    public let localName: String
    public let externalLabel: String?
    public let typeReference: TypeReference?
    public let slotName: String?

    public init(
        macros: [MacroApplication],
        localName: String,
        externalLabel: String?,
        typeReference: TypeReference?,
        slotName: String?
    ) {
        self.macros = macros
        self.localName = localName
        self.externalLabel = externalLabel
        self.typeReference = typeReference
        self.slotName = slotName
    }

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

    public init(
        macros: [MacroApplication],
        targetType: TypeReference?,
        name: String,
        hasExplicitParameterClause: Bool,
        parameters: [NeatFunctionParameter],
        returnType: TypeReference?,
        body: [Statement]?
    ) {
        self.macros = macros
        self.targetType = targetType
        self.name = name
        self.hasExplicitParameterClause = hasExplicitParameterClause
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
    }
}

public struct InitializerDeclaration {
    public let macros: [MacroApplication]
    public let parameters: [NeatFunctionParameter]
    public let body: [Statement]?

    public init(
        macros: [MacroApplication],
        parameters: [NeatFunctionParameter],
        body: [Statement]?
    ) {
        self.macros = macros
        self.parameters = parameters
        self.body = body
    }
}
