import Foundation

public enum ConstructKind {
    case entry
    case declaration
    case builder
}

public enum ConstructAttachment {
    case typeExtension(TypeExtensionDeclaration)
}

public struct ConstructDeclaration {
    public let kind: ConstructKind
    public let attribute: AttributeApplication?
    public let name: String
    public let conformances: [String]
    public let projectionTarget: String?
    public let attachments: [ConstructAttachment]
    public let states: [StateDeclaration]
    public let environments: [EnvironmentDeclaration]
    public let bindings: [BindingDeclaration]
    public let deriveds: [DerivedDeclaration]
    public let members: [MemberDeclaration]
    public let initializers: [InitializerDeclaration]
    public let callables: [CallableDeclaration]

    public var typeExtensions: [TypeExtensionDeclaration] {
        attachments.compactMap { attachment in
            switch attachment {
            case .typeExtension(let declaration):
                return declaration
            }
        }
    }
}
