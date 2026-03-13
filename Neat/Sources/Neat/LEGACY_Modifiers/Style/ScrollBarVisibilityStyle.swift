public struct ScrollBarVisibilityStyle: StyleModifier {
    public let visibility: ScrollBarVisibility

    public init(_ visibility: ScrollBarVisibility) {
        self.visibility = visibility
    }

    public var cssStyle: String? { nil }
    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] {
        [("data-scrollbar-visibility", visibility.rawValue)]
    }
}

public extension Component {
    func scrollBarVisibility(_ visibility: ScrollBarVisibility) -> some Component {
        style(ScrollBarVisibilityStyle(visibility))
    }
}
