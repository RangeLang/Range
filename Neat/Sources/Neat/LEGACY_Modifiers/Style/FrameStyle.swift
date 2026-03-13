public struct FrameStyle: StyleModifier {
    public let width: CSSUnit?
    public let height: CSSUnit?
    public let minWidth: CSSUnit?
    public let maxWidth: CSSUnit?
    public let minHeight: CSSUnit?
    public let maxHeight: CSSUnit?

    public init(
        width: CSSUnit? = nil,
        height: CSSUnit? = nil,
        minWidth: CSSUnit? = nil,
        maxWidth: CSSUnit? = nil,
        minHeight: CSSUnit? = nil,
        maxHeight: CSSUnit? = nil
    ) {
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    public var cssStyle: String? {
        var parts: [String] = []

        if let width {
            parts.append("width: \(width.cssValue);")
        }
        if let height {
            parts.append("height: \(height.cssValue);")
        }
        if let minWidth {
            parts.append("min-width: \(minWidth.cssValue);")
        }
        if let maxWidth {
            parts.append("max-width: \(maxWidth.cssValue);")
        }
        if let minHeight {
            parts.append("min-height: \(minHeight.cssValue);")
        }
        if let maxHeight {
            parts.append("max-height: \(maxHeight.cssValue);")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    func frame(
        width: CSSUnit? = nil,
        height: CSSUnit? = nil,
        minWidth: CSSUnit? = nil,
        maxWidth: CSSUnit? = nil,
        minHeight: CSSUnit? = nil,
        maxHeight: CSSUnit? = nil
    ) -> some Component {
        style(FrameStyle(
            width: width,
            height: height,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight
        ))
    }
}
