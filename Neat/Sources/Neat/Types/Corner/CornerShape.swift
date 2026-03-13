public enum CornerShape: Sendable {
    case round
    case square
    case bevel
    case notch
    case scoop
    case squircle
    case superellipse(Double)

    /// String descriptor suitable for storing in a custom property.
    var descriptor: String? {
        switch self {
        case .round:
            // Round is the default shape; we omit an explicit descriptor.
            return nil
        case .square:
            return "square"
        case .bevel:
            return "bevel"
        case .notch:
            return "notch"
        case .scoop:
            return "scoop"
        case .squircle:
            return "squircle"
        case .superellipse(let k):
            return "superellipse(\(k))"
        }
    }
}
