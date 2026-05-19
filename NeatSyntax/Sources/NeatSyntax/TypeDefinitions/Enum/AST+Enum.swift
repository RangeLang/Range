import Foundation

public struct EnumDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let conformances: [TypeReference]
    public let cases: [EnumCaseDeclaration]

    public var isCore: Bool {
        attribute?.isLanguageBoundary == true
            || macros.contains { $0.name == "language" || $0.name == "syntax" }
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
