public extension Color {
    /// Returns a new `Color` with its chroma (saturation) scaled by the given factor.
    ///
    /// - Parameter value:
    ///   - Values greater than `1.0` increase saturation.
    ///   - Values between `0.0` and `1.0` decrease saturation.
    ///   - Negative values are clamped to `0.0`.
    ///
    /// The resulting chroma is clamped into a safe `[0, 1]` range, and the
    /// alpha component is preserved.
    func saturation(_ value: Double) -> Color {
        let factor = max(0.0, value)

        switch self {
        case let .oklch(l, c, h, a):
            let newC = max(0.0, min(1.0, c * factor))
            return .oklch(l, newC, h, a)
        }
    }
}
