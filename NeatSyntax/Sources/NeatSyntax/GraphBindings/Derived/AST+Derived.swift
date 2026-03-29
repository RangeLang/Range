import Foundation

public struct DerivedDeclaration {
    public let macros: [MacroApplication]
    public let builderName: String?
    public let name: String
    public let typeName: String
    public let body: [Statement]?

    public init(
        macros: [MacroApplication],
        builderName: String?,
        name: String,
        typeName: String,
        body: [Statement]?
    ) {
        self.macros = macros
        self.builderName = builderName
        self.name = name
        self.typeName = typeName
        self.body = body
    }

    public var variadicElementTypeName: String? {
        guard typeName.hasSuffix("...") else {
            return nil
        }

        return String(typeName.dropLast(3))
    }

    public var isVariadic: Bool {
        variadicElementTypeName != nil
    }
}
