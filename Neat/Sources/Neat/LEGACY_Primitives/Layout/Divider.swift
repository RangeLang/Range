public struct Divider: _PrimitiveComponent {
    public init() {}

    public func build(in context: RenderContext?) -> ElementNode {
        if let context {
            context.registerPrimitiveUse(Self.componentName)
        }

        return ElementNode(
            tag: "div",
            classes: ["divider"]
        )
    }
}
