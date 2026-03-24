import Foundation

public struct EntityLowerer {
    public init() {}

    public func lower(_ construct: ConstructDeclaration) -> EntityDefinition {
        EntityDefinition(
            kind: lowerKind(construct.kind),
            identity: identity(for: construct.kind, name: construct.name),
            capabilities: capabilities(
                kind: construct.kind,
                states: construct.states
            ),
            states: construct.states.map(lowerState),
            environments: construct.environments.map(lowerEnvironment)
        )
    }

    private func lowerKind(_ kind: ConstructKind) -> EntityKind {
        switch kind {
        case .entry:
            return .entry
        case .declaration:
            return .declaration
        case .builder:
            return .builder
        }
    }

    private func identity(for kind: ConstructKind, name: String) -> EntityIdentity {
        EntityIdentity(symbol: name, stableID: "\(lowerKind(kind).rawValue):\(name)")
    }

    private func capabilities(
        kind: ConstructKind,
        states: [StateDeclaration]
    ) -> Set<EntityCapability> {
        var values: Set<EntityCapability> = []

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
}
