import Foundation

public enum EntityKind: String {
    case app
    case page
    case component
}

public enum EntityCapability: Hashable {
    case renderable
    case stateful
    case routable
    case compositionRoot
}

public struct EntityIdentity: Hashable {
    public let symbol: String
    public let stableID: String
}

public struct EntityStateField {
    public let name: String
    public let type: BuiltinType
    public let initialValue: Expression
}

public enum EntityAttachment {
    case neatEnum(EnumDeclaration)
    case neatFunction(NeatFunctionDeclaration)
    case typeExtension(TypeExtensionDeclaration)
    case neatProtocol(ProtocolDeclaration)
}

public struct EntityDefinition {
    public let kind: EntityKind
    public let identity: EntityIdentity
    public let capabilities: Set<EntityCapability>
    public let states: [EntityStateField]
    public let attachments: [EntityAttachment]
    public let body: ViewNode?
}
