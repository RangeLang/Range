@resultBuilder
public struct ComponentBuilder {

    // Lift any Component into the builder's internal representation
    public static func buildExpression<C: Component>(_ component: C) -> AnyComponent {
        AnyComponent(component)
    }

    // Base block (handles 0, 1, or many children).
    public static func buildBlock(_ components: AnyComponent...) -> AnyComponent {
        switch components.count {
        case 0:
            return AnyComponent(EmptyComponent())
        case 1:
            return components[0]
        default:
            return AnyComponent(FragmentComponent(components))
        }
    }

    // Optional
    public static func buildOptional(_ component: AnyComponent?) -> AnyComponent {
        component ?? AnyComponent(EmptyComponent())
    }

    // if / else
    public static func buildEither(first component: AnyComponent) -> AnyComponent {
        component
    }

    public static func buildEither(second component: AnyComponent) -> AnyComponent {
        component
    }

    // for-in loops
    public static func buildArray(_ components: [AnyComponent]) -> AnyComponent {
        AnyComponent(FragmentComponent(components))
    }

    // #available
    public static func buildLimitedAvailability(_ component: AnyComponent) -> AnyComponent {
        component
    }
}

@inline(__always)
public func Components(@ComponentBuilder _ content: () -> AnyComponent) -> AnyComponent {
    content()
}
