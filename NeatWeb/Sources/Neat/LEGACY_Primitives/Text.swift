public struct Text: _PrimitiveComponent {

    @AppEnvironment(\.textTag) private var environmentTextTag: TextTag

    public let content: String
    private let overrideTag: TextTag?

    public init(_ content: String) {
        self.content = content
        self.overrideTag = nil
    }

    init(content: String, overrideTag: TextTag?) {
        self.content = content
        self.overrideTag = overrideTag
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let tag = overrideTag ?? context?.environmentValues.textTag ?? .span

        // If context is nil (e.g. Untracked), we must NOT consume an ID to stay in sync with Server.
        let primitive: PrimitiveContext?
        if let context {
             primitive = PrimitiveContext.prepare(in: context, name: "text")
        } else {
             primitive = nil
        }

        let resolved = content
        if let primitive = primitive {
            #if os(WASI)
            neatLastRenderedTextID = primitive.index
            let bytes = Array(resolved.utf8)
            neatLastRenderedTextStorage = bytes
            neatLastRenderedTextLen = Int32(bytes.count)
            #endif
        }

        // If context is nil (e.g. inside Button/Link), default to span to avoid nested <div> inside <button>
        let tagName = (context == nil) ? "span" : tag.htmlTagName

        return ElementNode(
            tag: tagName,
            attributes: primitive?.attributes ?? [:],
            children: [.text(resolved)]
        )
    }
}

extension Text {
    public func textTag(_ tag: TextTag) -> Text {
        Text(content: content, overrideTag: tag)
    }
}
