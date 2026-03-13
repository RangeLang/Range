public struct Image: _PrimitiveComponent {
    public let source: String
    public let alt: String?

    public init(_ source: String, alt: String? = nil) {
        self.source = source
        self.alt = alt
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let primitive = PrimitiveContext.prepare(in: context, name: "Image")
        
        var attributes: [String: String] = primitive?.attributes ?? [:]
        attributes["src"] = source

        if let alt {
            attributes["alt"] = alt
        }

        return ElementNode(
            tag: "img",
            attributes: attributes
        )
    }
}

public extension Image {
    func loading(_ value: ImageLoading) -> some Component {
        style(ImageAttributeModifier([("loading", value.rawValue)]))
    }

    func decoding(_ value: ImageDecoding) -> some Component {
        style(ImageAttributeModifier([("decoding", value.rawValue)]))
    }

    func fetchPriority(_ value: ImageFetchPriority) -> some Component {
        style(ImageAttributeModifier([("fetchpriority", value.rawValue)]))
    }
}
