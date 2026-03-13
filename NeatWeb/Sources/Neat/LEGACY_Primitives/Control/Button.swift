public struct Button<Label: Component>: _PrimitiveComponent {
    public let label: Label
    public let action: () -> Void

    public init(action: @escaping () -> Void, @ComponentBuilder label: () -> Label) {
        self.label = label()
        self.action = action
    }

    public func build(in context: RenderContext?) -> ElementNode {
        buildButton(in: context, forwardedStyles: [])
    }

    private func buildButton(
        in context: RenderContext?,
        forwardedStyles: [any StyleModifier]
    ) -> ElementNode {

        let primitive = PrimitiveContext.prepare(
            in: context,
            name: Self.componentName,
            typeName: Self.typeName,
            event: "click",
            action: action
        )

        let style = context?.environmentValues.buttonStyle ?? .plain
        let labelComponent: AnyComponent
        if forwardedStyles.isEmpty {
            labelComponent = AnyComponent(label)
        } else {
            labelComponent = AnyComponent(ModifiedComponent(base: label, styles: forwardedStyles))
        }

        let configuration = ButtonStyleConfiguration(label: labelComponent)
        let styledLabel = StylePriorityContext.withPriority(-1) {
            style.makeBody(configuration: configuration)
        }

        let child = styledLabel.build(in: context)

        return ElementNode(
            tag: "button",
            attributes: primitive?.attributes ?? [:],
            children: [child]
        )
    }

}

extension Button: _StyleForwardingComponent {
    func _buildForwardingStyles(
        _ styles: [any StyleModifier],
        in context: RenderContext?
    ) -> ElementNode {
        buildButton(in: context, forwardedStyles: styles)
    }
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) {
        self.label = Text(title)
        self.action = action
    }
}
