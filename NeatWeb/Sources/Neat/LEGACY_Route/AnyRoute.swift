/// A type-erased `RouteComponent`.
///
/// This is the universal currency for the `@RouteBuilder`, allowing it
/// to compose different routing primitives together.
public struct AnyRoute: RouteComponent {
    private let _build: () -> [RouteNode]

    /// Erases the specific type of the provided route component.
    public init<R: RouteComponent>(_ route: R) {
        self._build = route.build
    }

    public func build() -> [RouteNode] {
        _build()
    }
}
