@resultBuilder
public struct RouteBuilder {

    /// Lifts any `RouteComponent` into the builder's `AnyRoute` representation.
    public static func buildExpression<R: RouteComponent>(_ component: R) -> AnyRoute {
        AnyRoute(component)
    }

    /// Combines multiple routes into a single `AnyRoute`.
    public static func buildBlock(_ components: AnyRoute...) -> AnyRoute {
        switch components.count {
        case 0:
            return AnyRoute(EmptyRoute())
        case 1:
            return components[0]
        default:
            return AnyRoute(RouteFragment(components))
        }
    }

    /// Handles `if` statements without an `else`.
    public static func buildOptional(_ component: AnyRoute?) -> AnyRoute {
        component ?? AnyRoute(EmptyRoute())
    }

    /// Handles `if/else` statements.
    public static func buildEither(first component: AnyRoute) -> AnyRoute {
        component
    }

    public static func buildEither(second component: AnyRoute) -> AnyRoute {
        component
    }

    /// Handles `for` loops.
    public static func buildArray(_ components: [AnyRoute]) -> AnyRoute {
        AnyRoute(RouteFragment(components))
    }
}

@inline(__always)
public func Routes(@RouteBuilder _ content: () -> AnyRoute) -> AnyRoute {
    content()
}
