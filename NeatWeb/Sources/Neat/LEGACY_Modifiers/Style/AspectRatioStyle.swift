public enum AspectRatioValue {
    case automatic
    case ratio(width: Double, height: Double)
}

public struct AspectRatioStyle: StyleModifier {
    public let value: AspectRatioValue

    public init(value: AspectRatioValue) {
        self.value = value
    }

    public var cssStyle: String? {
        switch value {
        case .automatic:
            return "aspect-ratio: auto"
        case .ratio(let width, let height):
            return "aspect-ratio: \(width) / \(height)"
        }
    }

    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    func aspectRatio(_ width: Double, _ height: Double) -> some Component {
        style(AspectRatioStyle(value: .ratio(width: width, height: height)))
    }

    func aspectRatio(_ value: AspectRatioValue) -> some Component {
        style(AspectRatioStyle(value: value))
    }
}
