import Foundation

public extension Color {
    /// Returns a new `Color` that linearly interpolates between this color
    /// and another color in OKLCH space, including the alpha channel.
    ///
    /// The `fraction` parameter is treated as a value in the closed range
    /// `0.0 ... 1.0` and is clamped accordingly:
    /// - 0.0 → 100% `self`, 0% `other`
    /// - 0.5 → 50% `self`, 50% `other`
    /// - 1.0 → 0% `self`, 100% `other`
    ///
    /// When both colors are expressed as `.oklch`, this performs a numeric
    /// interpolation of lightness, chroma, hue, and alpha. If, in the future,
    /// additional `Color` cases are introduced that cannot be represented
    /// as OKLCH, this helper will fall back to choosing one endpoint based
    /// on the fraction.
    func mix(with other: Color, by fraction: Double) -> Color {
        let t = max(0.0, min(1.0, fraction))

        switch (self, other) {
        case let (.oklch(l1, c1, h1, a1), .oklch(l2, c2, h2, a2)):
            let l = l1 + (l2 - l1) * t
            let c = c1 + (c2 - c1) * t
            let h = h1 + (h2 - h1) * t
            let a = a1 + (a2 - a1) * t
            return .oklch(l, c, h, a)

        default:
            // If we ever add non-OKLCH representations, fall back to
            // picking one endpoint so behavior is at least deterministic.
            return t < 0.5 ? self : other
        }
    }
}
