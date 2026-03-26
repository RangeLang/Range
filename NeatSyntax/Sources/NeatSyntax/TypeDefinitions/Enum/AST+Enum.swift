import Foundation

public struct EnumDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let name: String
    public let conformances: [TypeReference]
    public let cases: [EnumCaseDeclaration]
}

public struct EnumCaseDeclaration {
    public let name: String
    public let associatedValues: [AssociatedValueDeclaration]
}

public struct AssociatedValueDeclaration {
    public let label: String?
    public let typeName: String
}
