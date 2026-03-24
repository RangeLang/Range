import Foundation

public struct ProtocolDeclaration {
    public let attribute: AttributeApplication?
    public let primitive: PrimitiveModifier?
    public let name: String
    public let conformances: [String]

    public var isPrimitive: Bool {
        primitive != nil
    }
}
