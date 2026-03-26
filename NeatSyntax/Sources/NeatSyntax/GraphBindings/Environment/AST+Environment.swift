import Foundation

public struct EnvironmentDeclaration {
    public let macros: [MacroApplication]
    public let isState: Bool
    public let localName: String
    public let externalLabel: String?
    public let typeName: String

    public var name: String {
        localName
    }
}

public struct EnvironmentProvision {
    public let isState: Bool
    public let name: String
    public let typeName: String
    public let expression: Expression
}
