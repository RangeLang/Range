public struct EmptyHead: _PrimitiveHead {
    public init() {}

    public func build(in context: RenderContext?) -> ElementNode {
        .fragment([])
    }
}
