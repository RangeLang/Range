public struct VStack<Content: Component>: _PrimitiveComponent {
    public let alignment: Alignment
    public let spacing: Double?
    public let content: Content

    /// Creates a vertical stack of components using a flexbox column layout.
    ///
    /// - Parameters:
    ///   - alignment: Combined horizontal/vertical alignment of children.
    ///   - spacing: Optional gap between children, expressed in `rem` units.
    ///   - content: A `ComponentBuilder` closure that produces the stacked content.
    public init(
        alignment: Alignment = .topLeading,
        spacing: Double? = nil,
        @ComponentBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let childNode = content.build(in: context)

        let primitive = PrimitiveContext.prepare(
            in: context,
            name: Self.componentName
        )

        var styles: [String: StyleValue] = [:]
        if let spacing {
            styles["--stack-gap"] = StyleValue(value: "\(spacing)", priority: 0)
        } else {
            styles["--stack-gap"] = StyleValue(value: "0", priority: 0)
        }

        let hasSpacer = _stackNodeContainsSpacer(childNode)
        let hasHorizontalScrollArea = _stackNodeContainsHorizontalScrollArea(childNode)

        // When a Spacer is present, expand vertically to fill available height
        // so it can absorb remaining space; otherwise shrink-wrap contents.
        var classes: [String] = ["stack", "axis-vertical"]
        styles["--stack-display"] = StyleValue(value: (hasSpacer || hasHorizontalScrollArea) ? "flex" : "inline-flex", priority: 0)
        styles["--stack-direction"] = StyleValue(value: "column", priority: 0)

        // Cross axis (horizontal) alignment for a vertical stack.
        switch alignment.horizontal {
        case .leading:
            styles["--stack-align"] = StyleValue(value: "flex-start", priority: 0)
        case .center:
            styles["--stack-align"] = StyleValue(value: "center", priority: 0)
        case .trailing:
            styles["--stack-align"] = StyleValue(value: "flex-end", priority: 0)
        case .stretch:
            break
        }
        if hasHorizontalScrollArea, alignment.horizontal != .stretch {
            styles["--stack-align"] = StyleValue(value: "stretch", priority: 0)
        }

        // Main axis (vertical) alignment for a vertical stack.
        switch alignment.vertical {
        case .top:
            styles["--stack-justify"] = StyleValue(value: "flex-start", priority: 0)
        case .center:
            styles["--stack-justify"] = StyleValue(value: "center", priority: 0)
        case .bottom:
            styles["--stack-justify"] = StyleValue(value: "flex-end", priority: 0)
        case .stretch:
            break
        }

        if hasSpacer {
            classes.append("size")
            styles["--h"] = StyleValue(value: "100%", priority: 0)
        }
        if hasHorizontalScrollArea {
            classes.append("min-w-0")
        }

        return ElementNode(
            tag: "div",
            attributes: primitive?.attributes ?? [:],
            classes: classes,
            styleValues: styles,
            children: [childNode]
        )
    }
}
