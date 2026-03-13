public struct Island<Content: Component>: _PrimitiveComponent {
    public let name: String
    public let content: Content

    public init(_ name: String, @ComponentBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        // Islands are "isolated" parts of the tree (often for htmx or separate update logic).
        // For now, render a wrapper div.
        let childNode = content.build(in: context)
        
        return ElementNode(
            tag: "div",
            attributes: ["data-neat-island": "true"],
            children: [childNode]
        )
    }
}
