public struct AnyHead: _PrimitiveHead {
    private let _build: (RenderContext?) -> ElementNode

    public init<H: Head>(_ head: H) {
        self._build = head.build(in:)
    }

    public func build(in context: RenderContext?) -> ElementNode {
        _build(context)
    }
}
