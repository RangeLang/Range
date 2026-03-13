public enum Color {
    case oklch(l: Double, c: Double, h: Double, a: Double)
}

public extension Color {
    /// Convenience constructor for OKLCH colors with an optional alpha channel.
    /// When `a` is omitted, it defaults to 1.0 (fully opaque).
    static func oklch(_ l: Double, _ c: Double, _ h: Double, _ a: Double = 1.0) -> Color {
        .oklch(l: l, c: c, h: h, a: a)
    }
}

public extension Color {
    var cssValue: String {
        switch self {
        case .oklch(let l, let c, let h, let a):
            if a >= 1.0 {
                return "oklch(\(l) \(c) \(h))"
            } else {
                return "oklch(\(l) \(c) \(h) / \(a))"
            }
        }
    }
}
