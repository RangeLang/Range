import Foundation

public struct ProtocolDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let name: String
    public let conformances: [TypeReference]
}
