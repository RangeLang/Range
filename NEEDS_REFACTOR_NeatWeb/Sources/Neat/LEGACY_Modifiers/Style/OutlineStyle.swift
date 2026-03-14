public struct OutlineStyle: StyleModifier {
    public let width: Int?
    public let color: Color?
    public let lineStyle: LineStyle?

    public init(width: Int? = nil, color: Color? = nil, lineStyle: LineStyle? = nil) {
        self.width = width
        self.color = color
        self.lineStyle = lineStyle
    }

    public var cssStyle: String? {
        let w = width ?? 1
        var parts: [String] = [
            "--ow: \(w)px",
            "--os: \(lineStyle?.cssValue ?? "solid")"
        ]
        if let c = color {
            parts.append("--oc: \(c.cssValue)")
        }
        return parts.joined(separator: "; ")
    }

    public var cssClass: String? {
        "outline"
    }

    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    func outline(width: Int? = nil, color: Color? = nil, lineStyle: LineStyle? = nil) -> some Component {
        style(OutlineStyle(width: width, color: color, lineStyle: lineStyle))
    }
}
