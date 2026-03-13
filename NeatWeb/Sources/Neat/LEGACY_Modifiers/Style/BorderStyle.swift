public struct BorderStyle: StyleModifier {
    public let width: Int?
    public let color: Color?
    public let lineStyle: LineStyle?
    public let edges: EdgeSet

    public init(width: Int? = nil, color: Color? = nil, lineStyle: LineStyle? = nil, edges: EdgeSet = .all) {
        self.width = width
        self.color = color
        self.lineStyle = lineStyle
        self.edges = edges
    }

    // Prefer utility classes if possible; fall back to inline CSS when needed.
    public var cssStyle: String? {
        var parts: [String] = []
        if edges.isAll {
            if let w = width { parts.append("--bw: \(w)px") }
            if let c = color { parts.append("--bc: \(c.cssValue)") }
            if let s = lineStyle { parts.append("--bs: \(s.cssValue)") }
        } else {
            if let w = width {
                if edges.contains(.top)    { parts.append("border-top-width: \(w)px") }
                if edges.contains(.leading)  { parts.append("border-right-width: \(w)px") }
                if edges.contains(.bottom) { parts.append("border-bottom-width: \(w)px") }
                if edges.contains(.trailing)   { parts.append("border-left-width: \(w)px") }
            }
            if let c = color {
                if edges.contains(.top)    { parts.append("border-top-color: \(c.cssValue)") }
                if edges.contains(.leading)  { parts.append("border-right-color: \(c.cssValue)") }
                if edges.contains(.bottom) { parts.append("border-bottom-color: \(c.cssValue)") }
                if edges.contains(.trailing)   { parts.append("border-left-color: \(c.cssValue)") }
            }
            if let s = lineStyle {
                if edges.contains(.top)    { parts.append("border-top-style: \(s.cssValue)") }
                if edges.contains(.leading)  { parts.append("border-right-style: \(s.cssValue)") }
                if edges.contains(.bottom) { parts.append("border-bottom-style: \(s.cssValue)") }
                if edges.contains(.trailing)   { parts.append("border-left-style: \(s.cssValue)") }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    public var cssClass: String? {
        if edges.isAll {
            return "border"
        }
        return nil
    }

    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    func border(_ color: Color, width: Int? = nil, lineStyle: LineStyle? = nil, edges: EdgeSet = .all) -> some Component {
        style(BorderStyle(width: width, color: color, lineStyle: lineStyle, edges: edges))
    }

    func border(width: Int? = nil, color: Color? = nil, lineStyle: LineStyle? = nil, edges: EdgeSet = .all) -> some Component {
        style(BorderStyle(width: width, color: color, lineStyle: lineStyle, edges: edges))
    }
}
