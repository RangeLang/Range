/// Common line style for borders/outlines.
public enum LineStyle: String {
    case solid
    case dashed
    case dotted
    case double

    public var cssValue: String { rawValue }
    public var utilitySuffix: String { rawValue } // e.g., border-dashed, outline-dotted
}

