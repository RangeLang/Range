public struct FragmentComponent: _PrimitiveComponent {
    public let children: [AnyComponent]

    public init(_ children: [AnyComponent]) {
        self.children = children
    }

    public func build(in context: RenderContext?) -> ElementNode {
        .fragment(children.map { $0.build(in: context) })
    }
}
