public enum CSSUnit: Sendable {
    case px(Double)
    case rem(Double)
    case percent(Double)

    public static var fill: CSSUnit { .percent(100) }

    public var cssValue: String {
        switch self {
        case .px(let value):
            return "\(value)px"
        case .rem(let value):
            return "\(value)rem"
        case .percent(let value):
            return "\(value)%"
        }
    }
}

public func px(_ value: Double) -> CSSUnit { .px(value) }
public func rem(_ value: Double) -> CSSUnit { .rem(value) }
public func pct(_ value: Double) -> CSSUnit { .percent(value) }
