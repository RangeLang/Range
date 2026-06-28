import Foundation

public struct ValueDeclaration {
    public let macros: [MacroApplication]
    public let name: String
    public let typeName: String
    public let value: Expression?

    public init(
        macros: [MacroApplication],
        name: String,
        typeName: String,
        value: Expression?
    ) {
        self.macros = macros
        self.name = name
        self.typeName = typeName
        self.value = value
    }
}
