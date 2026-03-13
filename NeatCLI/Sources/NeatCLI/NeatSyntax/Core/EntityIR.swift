import Foundation

enum EntityKind: String {
    case app
    case page
    case component
}

enum EntityCapability: Hashable {
    case renderable
    case stateful
    case routable
    case compositionRoot
}

struct EntityIdentity: Hashable {
    let symbol: String
    let stableID: String
}

struct EntityStateField {
    let name: String
    let type: BuiltinType
    let initialValue: Expression
}

enum EntityAttachment {
    case neatEnum(EnumDeclaration)
    case neatFunction(NeatFunctionDeclaration)
    case styleModifier(StyleModifierDeclaration)
    case typeExtension(TypeExtensionDeclaration)
    case neatProtocol(ProtocolDeclaration)
}

struct EntityDefinition {
    let kind: EntityKind
    let identity: EntityIdentity
    let capabilities: Set<EntityCapability>
    let states: [EntityStateField]
    let attachments: [EntityAttachment]
    let body: ViewNode?
}
