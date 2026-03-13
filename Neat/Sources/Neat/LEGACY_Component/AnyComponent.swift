public struct AnyComponent: _PrimitiveComponent {
    private let _build: (RenderContext?) -> ElementNode
    internal let _base: Any

    public init<C: Component>(_ component: C) {
        self._build = component.build
        self._base = component
    }

    public func build(in context: RenderContext?) -> ElementNode {
        _build(context)
    }
}
