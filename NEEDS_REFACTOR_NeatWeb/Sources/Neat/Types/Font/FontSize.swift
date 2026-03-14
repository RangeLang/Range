import Foundation

public enum FontSize: Sendable {
    case title
    case subtitle
    case headline
    case subheadline
    case body
    case callout
    case caption

    /// Returns the concrete font-size in `rem` units for this token.
    var remValue: Double {
        switch self {
        case .title:       return 1.75
        case .subtitle:    return 1.5
        case .headline:    return 1.25
        case .subheadline: return 1.125
        case .body:        return 1.0
        case .callout:     return 0.875
        case .caption:     return 0.75
        }
    }
}

public extension FontSize {
    /// The concrete CSS value for this font size token, expressed in `rem`.
    /// Example: "1.0rem" for `.body`.
    var cssValue: String {
        "\(remValue)rem"
    }
}
