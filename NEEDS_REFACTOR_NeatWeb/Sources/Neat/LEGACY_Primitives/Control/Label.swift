public struct Label<Content: Component>: _PrimitiveComponent {
    public let title: String?
    public let content: Content
    public let spacing: Double?

    public init(
        _ title: String? = nil,
        spacing: Double? = nil,
        @ComponentBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
        self.spacing = spacing
    }

    public func build(in context: RenderContext?) -> ElementNode {
        if let context {
            context.registerPrimitiveUse(Self.componentName)
        }

        var children: [ElementNode] = []
        if let title, !title.isEmpty {
            children.append(Untracked(Text(title)).build(in: context))
        }
        children.append(content.build(in: context))

        var styles: [String: String] = [:]
        if let spacing {
            styles["--label-gap"] = "\(spacing)"
        }

        return ElementNode(
            tag: "label",
            styles: styles,
            children: children
        )
    }
}
