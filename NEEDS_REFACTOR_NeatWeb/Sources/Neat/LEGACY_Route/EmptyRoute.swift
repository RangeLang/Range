/// An internal `RouteComponent` that does nothing. Used for `if` statements without an `else`.
internal struct EmptyRoute: RouteComponent {
    func build() -> [RouteNode] {
        []
    }
}
