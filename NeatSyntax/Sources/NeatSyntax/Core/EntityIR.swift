import Foundation

public enum EntityKind: String {
    case entry
    case declaration
    case builder
}

public enum EntityCapability: Hashable {
    case renderable
    case stateful
}

public struct EntityIdentity: Hashable {
    public let symbol: String
    public let stableID: String
}

public struct EntityStateField {
    public let name: String
    public let type: BuiltinType
    public let storage: StateStorage
}

public struct EntityEnvironmentField {
    public let isState: Bool
    public let name: String
    public let typeName: String
}

public enum EntityAttachment {
    case typeExtension(TypeExtensionDeclaration)
}

public struct EntityDefinition {
    public let kind: EntityKind
    public let identity: EntityIdentity
    public let capabilities: Set<EntityCapability>
    public let states: [EntityStateField]
    public let environments: [EntityEnvironmentField]
    public let attachments: [EntityAttachment]
    public let body: ViewNode?
}
