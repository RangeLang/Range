public struct ScrollArea<Content: Component>: _PrimitiveComponent {
    public let axis: Axis
    public let content: Content

    public init(axis: Axis = .vertical, @ComponentBuilder content: () -> Content) {
        self.axis = axis
        self.content = content()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        var attributes: [String: String] = [
            "data-axis": axis.dataAttributeValue
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

        let contentNode = ElementNode(
            tag: "div",
            classes: ["scroll-content"],
            children: [content.build(in: context)]
        )
        let viewport = ElementNode(
            tag: "div",
            classes: ["scroll-viewport"],
            children: [contentNode]
        )

        var children: [ElementNode] = [viewport]

        if axis.contains(.vertical) {
            children.append(scrollBarNode(axis: .vertical))
        }
        if axis.contains(.horizontal) {
            children.append(scrollBarNode(axis: .horizontal))
        }

        return ElementNode(
            tag: "div",
            attributes: attributes,
            classes: ["scroll-area", axis.cssClass] + axis.fillClasses,
            children: children
        )
    }

    private func scrollBarNode(axis: Axis) -> ElementNode {
        ElementNode(
            tag: "div",
            classes: ["scroll-bar", axis.scrollBarClass],
            children: [
                ElementNode(
                    tag: "div",
                    classes: ["scroll-track"],
                    children: [
                        ElementNode(tag: "div", classes: ["scroll-thumb"])
                    ]
                )
            ]
        )
    }

}

extension Axis {
    fileprivate var dataAttributeValue: String {
        if contains([.horizontal, .vertical]) {
            return "both"
        } else if contains(.horizontal) {
            return "horizontal"
        } else {
            return "vertical"
        }
    }

    fileprivate var cssClass: String {
        if contains([.horizontal, .vertical]) {
            return "axis-both"
        } else if contains(.horizontal) {
            return "axis-horizontal"
        } else {
            return "axis-vertical"
        }
    }

    fileprivate var scrollBarClass: String {
        if contains(.horizontal) {
            return "horizontal"
        } else {
            return "vertical"
        }
    }

    fileprivate var fillClasses: [String] {
        var classes: [String] = []
        if contains(.vertical) {
            classes.append("min-h-0")
        }
        if contains(.horizontal) {
            classes.append("min-w-0")
        }
        return classes
    }
}
