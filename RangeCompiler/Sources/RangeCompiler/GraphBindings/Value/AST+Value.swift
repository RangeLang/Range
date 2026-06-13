import Foundation

public struct ValueDeclaration {
    public let macros: [MacroApplication]
    public let name: String
    public let typeName: String
    public let value: Expression?
}
