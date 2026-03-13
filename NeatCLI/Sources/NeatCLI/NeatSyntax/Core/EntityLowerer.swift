import Foundation

struct EntityLowerer {
    func lower(_ declaration: DeclarationNode) -> EntityDefinition {
        EntityDefinition(
            kind: lowerKind(declaration.kind),
            identity: identity(for: declaration.kind, name: declaration.name),
            capabilities: capabilities(
                kind: declaration.kind,
                states: declaration.states,
                hasBody: declaration.body != nil
            ),
            states: declaration.states.map(lowerState),
            attachments: declaration.objects.map(lowerAttachment),
            body: declaration.body
        )
    }

    func lower(_ component: ComponentNode) -> EntityDefinition {
        EntityDefinition(
            kind: lowerKind(component.kind),
            identity: identity(for: component.kind, name: component.name),
            capabilities: capabilities(
                kind: component.kind,
                states: component.states,
                hasBody: true
            ),
            states: component.states.map(lowerState),
            attachments: component.objects.map(lowerAttachment),
            body: component.body
        )
    }

    private func lowerKind(_ kind: DeclarationKind) -> EntityKind {
        switch kind {
        case .app:
            return .app
        case .page:
            return .page
        case .component:
            return .component
        }
    }

    private func identity(for kind: DeclarationKind, name: String) -> EntityIdentity {
        let rawKind: String
        switch kind {
        case .app:
            rawKind = "app"
        case .page:
            rawKind = "page"
        case .component:
            rawKind = "component"
        }

        return EntityIdentity(symbol: name, stableID: "\(rawKind):\(name)")
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

        switch kind {
        case .app:
            values.insert(.compositionRoot)
            values.insert(.routable)
        case .page:
            values.insert(.routable)
        case .component:
            break
        }

        return values
    }

    private func lowerState(_ state: StateDeclaration) -> EntityStateField {
        EntityStateField(
            name: state.name,
            type: state.type,
            initialValue: state.initialValue
        )
    }

    private func lowerAttachment(_ object: ObjectType) -> EntityAttachment {
        switch object {
        case .neatEnum(let declaration):
            return .neatEnum(declaration)
        case .neatFunction(let declaration):
            return .neatFunction(declaration)
        case .styleModifier(let declaration):
            return .styleModifier(declaration)
        case .typeExtension(let declaration):
            return .typeExtension(declaration)
        case .neatProtocol(let declaration):
            return .neatProtocol(declaration)
        }
    }
}
