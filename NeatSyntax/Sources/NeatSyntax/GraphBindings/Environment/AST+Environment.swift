import Foundation

public struct EnvironmentDeclaration {
    public let macros: [MacroApplication]
    public let isState: Bool
    public let localName: String
    public let externalLabel: String?
    public let type: TypeReference

    public var name: String {
        localName
    }

    public var typeName: String {
        type.displayName
    }
}

public struct EnvironmentProvision {
    public let isState: Bool
    public let name: String
    public let type: TypeReference
    public let expression: Expression

    public var typeName: String {
        type.displayName
    }
}
