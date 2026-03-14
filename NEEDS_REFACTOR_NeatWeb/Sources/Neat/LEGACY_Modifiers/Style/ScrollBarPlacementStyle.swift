public struct ScrollBarPlacementStyle: StyleModifier {
    public let placement: ScrollBarPlacement

    public init(_ placement: ScrollBarPlacement) {
        self.placement = placement
    }

    public var cssStyle: String? { nil }
    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] {
        [("data-scrollbar-placement", placement.rawValue)]
    }
}

public extension Component {
    func scrollBarPlacement(_ placement: ScrollBarPlacement) -> some Component {
        style(ScrollBarPlacementStyle(placement))
    }
}
