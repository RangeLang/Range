public struct ItalicStyle: StyleModifier {

    public init() {}

    public var cssStyle: String? {
        "font-style: italic"
    }

    public var cssClass: String? { nil }

    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    /// Applies italic font style to this component's root element.
    func italic() -> some Component {
        style(ItalicStyle())
    }
}
