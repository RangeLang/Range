public struct ZStackItemAlignmentStyle: StyleModifier {
    public let alignment: Alignment

    public init(_ alignment: Alignment) {
        self.alignment = alignment
    }

    public var cssStyle: String? {
        var parts: [String] = []
        switch alignment.vertical {
        case .top:
            parts.append("align-self: start")
        case .center:
            parts.append("align-self: center")
        case .bottom:
            parts.append("align-self: end")
        case .stretch:
            parts.append("align-self: stretch")
        }

        switch alignment.horizontal {
        case .leading:
            parts.append("justify-self: start")
        case .center:
            parts.append("justify-self: center")
        case .trailing:
            parts.append("justify-self: end")
        case .stretch:
            parts.append("justify-self: stretch")
        }

        return parts.joined(separator: "; ")
    }

    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    func zStackAlignment(_ alignment: Alignment) -> some Component {
        style(ZStackItemAlignmentStyle(alignment))
    }
}
