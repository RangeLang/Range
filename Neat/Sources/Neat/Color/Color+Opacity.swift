/// Opacity helpers for `Color` in OKLCH space.
public extension Color {
    /// Returns a new `Color` with the given alpha applied in OKLCH output.
    ///
    /// This does not simulate blending over a background; instead it adjusts
    /// the stored alpha channel so that CSS can emit `oklch(l c h / a)`.
    ///
    /// The effect is multiplicative: calling `.opacity(0.5)` on a color that
    /// already has `a = 0.5` will result in `a = 0.25`.
    ///
    /// - Parameter alpha: Desired opacity factor in the range `0.0 ... 1.0`.
    ///   Values outside this range are clamped.
    func opacity(_ alpha: Double) -> Color {
        let factor = max(0.0, min(1.0, alpha))

        switch self {
        case let .oklch(l, c, h, currentA):
            let newA = currentA * factor
            return .oklch(l, c, h, newA)
        }
    }
}
