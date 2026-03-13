public struct Portal<Content: Component>: _PrimitiveComponent {
    public let target: String
    public let content: Content

    public init(
        target: String = "body",
        @ComponentBuilder content: () -> Content
    ) {
        self.target = target
        self.content = content()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        var attributes: [String: String] = [
            "data-portal-target": target
        ]

        if let context {
            let primitive = PrimitiveContext.prepare(
                in: context,
                name: Self.componentName,
                typeName: Self.typeName
            )
            if let primitive {
                attributes.merge(primitive.attributes) { _, newValue in newValue }
            }
        }

        let child = content.build(in: context)

        return ElementNode(
            tag: "div",
            attributes: attributes,
            styles: ["display": "contents"],
            children: [child]
        )
    }

}
