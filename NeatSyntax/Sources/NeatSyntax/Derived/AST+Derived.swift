import Foundation

public struct DerivedDeclaration {
    public let builderName: String?
    public let name: String
    public let typeName: String
    public let body: [Statement]?

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
