public struct TextField: Component {
    @Binding public var text: String
    public let placeholder: String?

    @AppEnvironment(\.textFieldStyle) private var textFieldStyle

    public init(_ placeholder: String? = nil, text: Binding<String>) {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some Component {
        let base = _TextFieldPrimitive(
            placeholder: placeholder,
            text: _text
        )
        let configuration = TextFieldStyleConfiguration(textField: AnyComponent(base))
        return StylePriorityContext.withPriority(-1) {
            textFieldStyle.makeBody(configuration: configuration)
        }
    }

    public func build(in context: RenderContext?) -> ElementNode {
        body.build(in: context)
    }
}

private struct _TextFieldPrimitive: _PrimitiveComponent {
    @Binding var text: String
    let placeholder: String?

    init(placeholder: String?, text: Binding<String>) {
        self._text = text
        self.placeholder = placeholder
    }

    static var primitiveName: String { "TextField" }
    static var componentName: String { "text-field" }

    func build(in context: RenderContext?) -> ElementNode {
        var attributes: [String: String] = [
            "type": "text",
            "value": text
        ]

        if let placeholder {
            attributes["placeholder"] = placeholder
        }

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
            tag: "input",
            attributes: attributes,
            children: []
        )
    }

}
