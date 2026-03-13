public struct EmptyComponent: _PrimitiveComponent {
    public init() {}

    public func build(in context: RenderContext?) -> ElementNode {
        .fragment([])
    }
}
