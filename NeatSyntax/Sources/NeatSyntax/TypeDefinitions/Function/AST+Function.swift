import Foundation

public struct NeatFunctionParameter {
    public let macros: [MacroApplication]
    public let localName: String
    public let externalLabel: String?
    public let typeReference: TypeReference?
    public let slotName: String?
    public let capturesSyntax: Bool

    public init(
        macros: [MacroApplication],
        localName: String,
        externalLabel: String?,
        typeReference: TypeReference?,
        slotName: String?,
        capturesSyntax: Bool = false
    ) {
        self.macros = macros
        self.localName = localName
        self.externalLabel = externalLabel
        self.typeReference = typeReference
        self.slotName = slotName
        self.capturesSyntax = capturesSyntax
    }

    public var name: String {
        localName
    }

    public var isOptional: Bool {
        guard case .optional = typeReference else { return false }
        return true
    }

    public var renderedTypeName: String? {
        guard let typeReference else {
            return nil
        }
        if capturesSyntax {
            return "capture \(typeReference.displayName)"
        }
        return typeReference.displayName
    }
}

public struct CallableDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let targetType: TypeReference?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let hasExplicitParameterClause: Bool
    public let parameters: [NeatFunctionParameter]
    public let returnType: TypeReference?
    public let body: [Statement]?

    public init(
        macros: [MacroApplication],
        attribute: AttributeApplication?,
        targetType: TypeReference?,
        name: String,
        genericParameters: [GenericParameter],
        hasExplicitParameterClause: Bool,
        parameters: [NeatFunctionParameter],
        returnType: TypeReference?,
        body: [Statement]?
    ) {
        self.macros = macros
        self.attribute = attribute
        self.targetType = targetType
        self.name = name
        self.genericParameters = genericParameters
        self.hasExplicitParameterClause = hasExplicitParameterClause
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
    }

    public var isCore: Bool {
        attribute?.name == "core"
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
