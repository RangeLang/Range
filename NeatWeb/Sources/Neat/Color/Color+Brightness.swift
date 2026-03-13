public extension Color {
    /// Returns a new `Color` with its lightness adjusted by the given value.
    ///
    /// - Parameter value: A value added to the lightness component `l`,
    ///   clamped to the [0.0, 1.0] range.
    ///   - Positive values lighten the color.
    ///   - Negative values darken the color.
    ///
    /// The alpha component is preserved.
    func brightness(_ value: Double) -> Color {
        switch self {
        case let .oklch(l, c, h, a):
            let newL = max(0.0, min(1.0, l + value))
            return .oklch(newL, c, h, a)
        }
    }
}
