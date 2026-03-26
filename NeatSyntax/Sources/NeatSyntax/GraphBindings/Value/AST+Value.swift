import Foundation

public struct ValueDeclaration {
    public let macros: [MacroApplication]
    public let localName: String
    public let externalLabel: String?
    public let typeName: String
    public let value: Expression?

    public var name: String {
        localName
    }
}
