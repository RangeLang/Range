import Foundation

public struct RangeFunctionParameter {
    public let macros: [MacroApplication]
    public let name: String
    public let typeReference: TypeReference?
    public let defaultValue: Expression?
    public let slotName: String?
    public let isBinding: Bool
    public let capturesSyntax: Bool
    public let captureMetadataType: TypeReference?

    public init(
        macros: [MacroApplication],
        name: String,
        typeReference: TypeReference?,
        defaultValue: Expression? = nil,
        slotName: String?,
        isBinding: Bool = false,
        capturesSyntax: Bool = false,
        captureMetadataType: TypeReference? = nil
    ) {
        self.macros = macros
        self.name = name
        self.typeReference = typeReference
        self.defaultValue = defaultValue
        self.slotName = slotName
        self.isBinding = isBinding
        self.capturesSyntax = capturesSyntax
        self.captureMetadataType = captureMetadataType
    }

    public var localName: String {
        name
    }

    public var isOptional: Bool {
        guard case .optional = typeReference else { return false }
        return true
    }

    public var renderedTypeName: String? {
        guard let typeReference else {
            return nil
        }
        if isBinding {
            return "binding \(typeReference.displayName)"
        }
        if capturesSyntax {
            let metadata = captureMetadataType.map { "<\($0.displayName)>" } ?? ""
            return "@capture\(metadata) \(typeReference.displayName)"
        }
        return typeReference.displayName
    }
}

public struct CallableDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let targetType: TypeReference?
    public let receiverType: TypeReference?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let hasExplicitParameterClause: Bool
    public let parameters: [RangeFunctionParameter]
    public let returnType: TypeReference?
    public let body: [Statement]?

    public init(
        macros: [MacroApplication],
        attribute: AttributeApplication?,
        targetType: TypeReference?,
        receiverType: TypeReference? = nil,
        name: String,
        genericParameters: [GenericParameter],
        hasExplicitParameterClause: Bool,
        parameters: [RangeFunctionParameter],
        returnType: TypeReference?,
        body: [Statement]?
    ) {
        self.macros = macros
        self.attribute = attribute
        self.targetType = targetType
        self.receiverType = receiverType
        self.name = name
        self.genericParameters = genericParameters
        self.hasExplicitParameterClause = hasExplicitParameterClause
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
    }

    public var isCore: Bool {
        attribute?.isLanguageBoundary == true
            || macros.contains { $0.name == "language" || $0.name == "syntax" }
    }

    public var isPackaging: Bool {
        attribute?.isPackaging == true
    }
}

public struct InitializerDeclaration {
    public let macros: [MacroApplication]
    public let parameters: [RangeFunctionParameter]
    public let returnType: TypeReference?
    public let body: [Statement]?

    public init(
        macros: [MacroApplication],
        parameters: [RangeFunctionParameter],
        returnType: TypeReference? = nil,
        body: [Statement]?
    ) {
        self.macros = macros
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
    }
}
