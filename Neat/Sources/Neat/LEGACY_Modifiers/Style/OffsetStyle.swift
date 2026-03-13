public struct OffsetStyle: StyleModifier {
    public let offset: Offset

    public init(_ offset: Offset) {
        self.offset = offset
    }

    public var cssStyle: String? {
        "--ox: \(offset.x)px; --oy: \(offset.y)px"
    }

    public var cssClass: String? { "offset" }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    func offset(_ offset: Offset) -> some Component {
        style(OffsetStyle(offset))
    }

    func offset(x: Int, y: Int) -> some Component {
        style(OffsetStyle(Offset(x: x, y: y)))
    }
}
