import Foundation

public struct ProtocolDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let primitive: PrimitiveModifier?
    public let name: String
    public let conformances: [TypeReference]

    public var isPrimitive: Bool {
        primitive != nil
    }
}
