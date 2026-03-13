public struct Meta: _PrimitiveHead {
    let attributes: [String: String]

    public init(_ attributes: [String: String]) {
        self.attributes = attributes
    }

    public func build(in context: RenderContext?) -> ElementNode {
        ElementNode(
            tag: "meta",
            attributes: attributes
        )
    }
}

public extension Meta {


    static func description(_ text: String) -> some Head {
        Meta(["name": "description", "content": text])
    }

    static func robots(_ value: String) -> some Head {
        Meta(["name": "robots", "content": value])
    }

    static func keywords(_ value: String) -> some Head {
        Meta(["name": "keywords", "content": value])
    }

    static func viewport(_ value: String = "width=device-width, initial-scale=1") -> some Head {
        Meta(["name": "viewport", "content": value])
    }

    static func charset(_ value: String = "utf-8") -> some Head {
        Meta(["charset": value])
    }

    static func themeColor(_ hex: String) -> some Head {
        Meta(["name": "theme-color", "content": hex])
    }

    static func ogTitle(_ text: String) -> some Head {
        Meta(["property": "og:title", "content": text])
    }

    static func ogDescription(_ text: String) -> some Head {
        Meta(["property": "og:description", "content": text])
    }

    static func ogURL(_ url: String) -> some Head {
        Meta(["property": "og:url", "content": url])
    }

    static func ogType(_ type: String) -> some Head {
        Meta(["property": "og:type", "content": type])
    }

    static func ogImage(_ url: String) -> some Head {
        Meta(["property": "og:image", "content": url])
    }

    static func twitterCard(_ value: String = "summary") -> some Head {
        Meta(["name": "twitter:card", "content": value])
    }

    static func twitterTitle(_ text: String) -> some Head {
        Meta(["name": "twitter:title", "content": text])
    }

    static func twitterDescription(_ text: String) -> some Head {
        Meta(["name": "twitter:description", "content": text])
    }

    static func twitterSite(_ handle: String) -> some Head {
        Meta(["name": "twitter:site", "content": handle])
    }

    static func twitterImage(_ url: String) -> some Head {
        Meta(["name": "twitter:image", "content": url])
    }


}
