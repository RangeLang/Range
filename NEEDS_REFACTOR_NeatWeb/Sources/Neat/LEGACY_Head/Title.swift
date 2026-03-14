struct TitleHead: _PrimitiveHead {
    let text: String

	public func build(in context: RenderContext?) -> ElementNode {
	    ElementNode(
	        tag: "title",
	        children: [.text(text)]
	    )
	}
}

public extension Meta {
    static func title(_ text: String) -> some Head {
        TitleHead(text: text)
    }
}
