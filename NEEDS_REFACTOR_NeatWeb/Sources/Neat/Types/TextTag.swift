public enum TextTag: Sendable {
    case span
    case p
    case h1, h2, h3, h4, h5, h6
}

public extension TextTag {
    var htmlTagName: String {
        switch self {
        case .span:
            return "span"
        case .p:
            return "p"
        case .h1:
            return "h1"
        case .h2:
            return "h2"
        case .h3:
            return "h3"
        case .h4:
            return "h4"
        case .h5:
            return "h5"
        case .h6:
            return "h6"
        }
    }
}
