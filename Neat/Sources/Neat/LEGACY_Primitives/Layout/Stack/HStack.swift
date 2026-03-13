public struct HStack<Content: Component>: _PrimitiveComponent {
    public let alignment: Alignment
    public let spacing: Double?
    public let content: Content

    /// Creates a horizontal stack of components using a flexbox row layout.
    ///
    /// - Parameters:
    ///   - alignment: Combined horizontal/vertical alignment of children.
    ///   - fillsWidth: If `true`, the stack will occupy the full available
    ///     width. If `false`, it will shrink to fit its contents.
    ///   - spacing: Optional gap between children, expressed in `rem` units.
    ///   - content: A `ComponentBuilder` closure that produces the stacked content.
    public init(
        alignment: Alignment = .leading,
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
        let hasScrollArea = _stackNodeContainsScrollArea(childNode)

        // When a Spacer is present, expand to fill available width so the
        // spacer can absorb remaining space. Otherwise, shrink-wrap contents.
        var classes: [String] = ["stack", "axis-horizontal"]
        styles["--stack-display"] = StyleValue(
            value: (hasSpacer || hasScrollArea) ? "flex" : "inline-flex", priority: 0)
        styles["--stack-direction"] = StyleValue(value: "row", priority: 0)
        if hasSpacer {
            classes.append("size")
            styles["--w"] = StyleValue(value: "100%", priority: 0)
        }
        if hasScrollArea {
            classes.append("min-h-0")
        }

        // Main axis (horizontal) alignment for a horizontal stack.
        switch alignment.horizontal {
        case .leading:
            styles["--stack-justify"] = StyleValue(value: "flex-start", priority: 0)
        case .center:
            styles["--stack-justify"] = StyleValue(value: "center", priority: 0)
        case .trailing:
            styles["--stack-justify"] = StyleValue(value: "flex-end", priority: 0)
        case .stretch:
            // Future: could map to space-between/around/evenly.
            break
        }

        // Cross axis (vertical) alignment for a horizontal stack.
        switch alignment.vertical {
        case .top:
            styles["--stack-align"] = StyleValue(value: "flex-start", priority: 0)
        case .center:
            styles["--stack-align"] = StyleValue(value: "center", priority: 0)
        case .bottom:
            styles["--stack-align"] = StyleValue(value: "flex-end", priority: 0)
        case .stretch:
            break
        }
        if hasScrollArea, alignment.vertical != .stretch {
            styles["--stack-align"] = StyleValue(value: "stretch", priority: 0)
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
