import Foundation

public enum EntityKind: String {
    case entry
    case declaration
    case builder
}

public enum EntityCapability: Hashable {
    case stateful
}

public struct EntityIdentity: Hashable {
    public let symbol: String
    public let stableID: String
}

public struct EntityStateField {
    public let name: String
    public let type: TypeReference
    public let storage: StateStorage
}

public struct EntityDefinition {
    public let kind: EntityKind
    public let identity: EntityIdentity
    public let capabilities: Set<EntityCapability>
    public let states: [EntityStateField]
}
