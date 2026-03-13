public struct Stylesheet: _PrimitiveHead {
    public let href: String

    public init(_ href: String) {
        self.href = href
    }

    public func build(in context: RenderContext?) -> ElementNode {
        ElementNode(
            tag: "link",
            attributes: [
                "rel": "stylesheet",
                "href": href
            ]
        )
    }
}
