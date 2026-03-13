import Foundation

/// Semantic font weight tokens used by typography-related modifiers.
/// The specific numeric values are chosen to align roughly with common
/// CSS `font-weight` ranges and SwiftUI's `Font.Weight` cases.
public enum FontWeight: Sendable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black
}

public extension FontWeight {
    /// Numeric CSS `font-weight` value corresponding to this token.
    /// These can be used directly in declarations like `font-weight: 600`.
    var numericValue: Int {
        switch self {
        case .ultraLight: return 100
        case .thin:       return 200
        case .light:      return 300
        case .regular:    return 400
        case .medium:     return 500
        case .semibold:   return 600
        case .bold:       return 700
        case .heavy:      return 800
        case .black:      return 900
        }
    }

    /// Convenience string form suitable for interpolating into CSS as a
    /// concrete numeric `font-weight` value.
    var cssValue: String {
        "\(numericValue)"
    }
}
