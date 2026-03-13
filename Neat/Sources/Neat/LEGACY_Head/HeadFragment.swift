public struct HeadFragment: _PrimitiveHead {
    public let items: [AnyHead]

    public init(_ items: [AnyHead]) {
        self.items = items
    }

    public func build(in context: RenderContext?) -> ElementNode {
        .fragment(items.map { $0.build(in: context) })
    }
}
