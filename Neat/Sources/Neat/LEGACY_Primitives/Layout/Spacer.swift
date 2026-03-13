public struct Spacer: _PrimitiveComponent {
    public init() {}

    public func build(in context: RenderContext?) -> ElementNode {
        // A Spacer usually just takes up flexible space in a Stack.
        // We can render it as a div with `flex-grow: 1`.
        return ElementNode(
            tag: "div",
            styleValues: ["flex-grow": StyleValue(value: "1", priority: 0)]
        )
    }
}
