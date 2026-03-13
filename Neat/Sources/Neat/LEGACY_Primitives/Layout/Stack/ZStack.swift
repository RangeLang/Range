public struct ZStack<Content: Component>: _PrimitiveComponent {
    public let alignment: Alignment
    public let content: Content

    public init(
        alignment: Alignment = .center,
        @ComponentBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let built = content.build(in: context)
        let nodes: [ElementNode]
        switch built {
        case .fragment(let children):
            nodes = children
        default:
            nodes = [built]
        }

        let primitive = PrimitiveContext.prepare(
            in: context,
            name: Self.componentName
        )
        
        var styles: [String: StyleValue] = [:]
        switch alignment.vertical {
        case .top:
            styles["--z-align"] = StyleValue(value: "start", priority: 0)
        case .center:
            styles["--z-align"] = StyleValue(value: "center", priority: 0)
        case .bottom:
            styles["--z-align"] = StyleValue(value: "end", priority: 0)
        case .stretch:
            styles["--z-align"] = StyleValue(value: "stretch", priority: 0)
        }

        switch alignment.horizontal {
        case .leading:
            styles["--z-justify"] = StyleValue(value: "start", priority: 0)
        case .center:
            styles["--z-justify"] = StyleValue(value: "center", priority: 0)
        case .trailing:
            styles["--z-justify"] = StyleValue(value: "end", priority: 0)
        case .stretch:
            styles["--z-justify"] = StyleValue(value: "stretch", priority: 0)
        }

        let wrapped = nodes.enumerated().map { index, node in
            switch node {
            case .element(let tag, let attributes, var classes, let styles, let children):
                if styles["display"]?.value == "contents" {
                    return ElementNode(
                        tag: "div",
                        classes: ["zstack-item"],
                        styleValues: ["z-index": StyleValue(value: "\(index)", priority: 0)],
                        children: [node]
                    )
                }
                var nextStyles = styles
                if !classes.contains("zstack-item") {
                    classes.append("zstack-item")
                }
                nextStyles["z-index"] = StyleValue(value: "\(index)", priority: 0)
                return ElementNode.element(
                    tag: tag,
                    attributes: attributes,
                    classes: classes,
                    styles: nextStyles,
                    children: children
                )
            default:
                return ElementNode(
                    tag: "div",
                    classes: ["zstack-item"],
                    styleValues: ["z-index": StyleValue(value: "\(index)", priority: 0)],
                    children: [node]
                )
            }
        }

        return ElementNode(
            tag: "div",
            attributes: primitive?.attributes ?? [:],
            classes: ["zstack"],
            styleValues: styles,
            children: wrapped
        )
    }
}
