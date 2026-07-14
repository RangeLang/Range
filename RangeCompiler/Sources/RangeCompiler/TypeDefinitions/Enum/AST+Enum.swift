import Foundation

public enum EnumExtensibility {
    case open
    case closed
}

public struct EnumDeclaration {
    public let macros: [MacroApplication]
    public let extensibility: EnumExtensibility
    public let attribute: AttributeApplication?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let conformances: [TypeReference]
    public let cases: [EnumCaseDeclaration]

    public init(
        macros: [MacroApplication],
        extensibility: EnumExtensibility,
        attribute: AttributeApplication?,
        name: String,
        genericParameters: [GenericParameter],
        conformances: [TypeReference],
        cases: [EnumCaseDeclaration]
    ) {
        self.macros = macros
        self.extensibility = extensibility
        self.attribute = attribute
        self.name = name
        self.genericParameters = genericParameters
        self.conformances = conformances
        self.cases = cases
    }

    public var isCore: Bool {
        attribute?.isBuiltinBoundary == true
            || macros.contains { $0.name == "syntax" }
    }

    public var isPackaging: Bool {
        attribute?.isPackaging == true
    }
}

public struct EnumCaseDeclaration {
    public let name: String
    public let associatedValues: [AssociatedValueDeclaration]
}

public struct AssociatedValueDeclaration {
    public let label: String?
    public let typeReference: TypeReference
}
