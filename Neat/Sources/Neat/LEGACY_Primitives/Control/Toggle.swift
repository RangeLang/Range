public struct Toggle: Component {
    @Binding public var isOn: Bool

    @AppEnvironment(\.toggleStyle) private var toggleStyle

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some Component {
        let base = _TogglePrimitive(isOn: _isOn)
        let configuration = ToggleStyleConfiguration(isOn: _isOn.wrappedValue, toggle: AnyComponent(base))
        return StylePriorityContext.withPriority(-1) {
            toggleStyle.makeBody(configuration: configuration)
        }
    }

    public func build(in context: RenderContext?) -> ElementNode {
        body.build(in: context)
    }
}

private struct _TogglePrimitive: _PrimitiveComponent {
    @Binding var isOn: Bool

    init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    static var primitiveName: String { "Toggle" }
    static var componentName: String { "toggle" }

    func build(in context: RenderContext?) -> ElementNode {
        var attributes: [String: String] = [
            "tabindex": "0"
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

        return ElementNode(
            tag: "div",
            attributes: attributes,
            children: []
        )
    }

}
