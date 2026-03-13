public struct ScrollBarBehaviorStyle: StyleModifier {
    public let behavior: ScrollBarBehavior

    public init(_ behavior: ScrollBarBehavior) {
        self.behavior = behavior
    }

    public var cssStyle: String? { nil }
    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] {
        [("data-scrollbar-behavior", behavior.rawValue)]
    }
}

public extension Component {
    func scrollBarBehavior(_ behavior: ScrollBarBehavior) -> some Component {
        style(ScrollBarBehaviorStyle(behavior))
    }
}
