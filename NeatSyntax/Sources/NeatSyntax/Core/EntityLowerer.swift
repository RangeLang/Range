import Foundation

public struct EntityLowerer {
    public init() {}

    public func lower(_ declaration: DeclarationNode) -> EntityDefinition {
        EntityDefinition(
            kind: lowerKind(declaration.kind),
            identity: identity(for: declaration.kind, name: declaration.name),
            capabilities: capabilities(
                kind: declaration.kind,
                states: declaration.states,
                hasBody: declaration.body != nil
            ),
            states: declaration.states.map(lowerState),
            environments: declaration.environments.map(lowerEnvironment),
            attachments: declaration.objects.map(lowerAttachment),
            body: declaration.body
        )
    }

    public func lower(_ component: ComponentNode) -> EntityDefinition {
        EntityDefinition(
            kind: lowerKind(component.kind),
            identity: identity(for: component.kind, name: component.name),
            capabilities: capabilities(
                kind: component.kind,
                states: component.states,
                hasBody: true
            ),
            states: component.states.map(lowerState),
            environments: component.environments.map(lowerEnvironment),
            attachments: component.objects.map(lowerAttachment),
            body: component.body
        )
    }

    private func lowerKind(_ kind: DeclarationKind) -> EntityKind {
        switch kind {
        case .entry:
            return .entry
        case .declaration:
            return .declaration
        }
    }

    private func identity(for kind: DeclarationKind, name: String) -> EntityIdentity {
        EntityIdentity(symbol: name, stableID: "\(lowerKind(kind).rawValue):\(name)")
    }

    private func capabilities(
        kind: DeclarationKind,
        states: [StateDeclaration],
        hasBody: Bool
    ) -> Set<EntityCapability> {
        var values: Set<EntityCapability> = []

        if hasBody {
            values.insert(.renderable)
        }
        if !states.isEmpty {
            values.insert(.stateful)
        }

        return values
    }

    private func lowerState(_ state: StateDeclaration) -> EntityStateField {
        EntityStateField(
            name: state.name,
            type: state.type,
            storage: state.storage
        )
    }

    private func lowerEnvironment(_ environment: EnvironmentDeclaration) -> EntityEnvironmentField {
        EntityEnvironmentField(
            isState: environment.isState,
            name: environment.name,
            typeName: environment.typeName
        )
    }

    private func lowerAttachment(_ object: ObjectType) -> EntityAttachment {
        switch object {
        case .typeExtension(let declaration):
            return .typeExtension(declaration)
        }
    }
}
