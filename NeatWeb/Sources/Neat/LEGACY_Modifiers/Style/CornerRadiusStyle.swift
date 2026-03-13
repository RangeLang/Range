

public struct CornerRadiusStyle: StyleModifier {
    /// Radius in spacing units (multiplied by `--space-unit`).
    public let value: Double

    /// Corners that should receive this radius.
    public let corners: CornerSet

    /// Desired corner shape. Today this is recorded into a custom property and
    /// does not change the generated CSS, but it provides a forward-compatible
    /// hook for future `corner-shape` support.
    public let shape: CornerShape

    public init(
        value: Double,
        corners: CornerSet = .all,
        shape: CornerShape = .round
    ) {
        self.value = value
        self.corners = corners
        self.shape = shape
    }

    /// Variable-based corner radius; the `.corner-radius` utility in CSS reads:
    /// - `--cr` as the uniform radius (all corners), and
    /// - `--cr-tl`, `--cr-tr`, `--cr-br`, `--cr-bl` as per-corner overrides.
    ///
    /// The selected `shape` is recorded into `--cr-shape` as a string descriptor
    /// for future use by runtimes or newer CSS features, but it is not currently
    /// interpreted by the generated CSS.
    public var cssStyle: String? {
        let r = value

        var parts: [String] = []

        // Shape descriptor hint (not yet consumed by CSS).
        if let descriptor = shape.descriptor {
            parts.append("--cr-shape: \(descriptor);")

            // Emit per-corner `corner-*-shape` declarations so that browsers
            // with `corner-shape` support can consume them when available.
            let token = descriptor
            if corners == .all {
                parts.append("corner-top-left-shape: \(token);")
                parts.append("corner-top-right-shape: \(token);")
                parts.append("corner-bottom-right-shape: \(token);")
                parts.append("corner-bottom-left-shape: \(token);")
            } else {
                if corners.contains(.topLeading) {
                    parts.append("corner-top-left-shape: \(token);")
                }
                if corners.contains(.topTrailing) {
                    parts.append("corner-top-right-shape: \(token);")
                }
                if corners.contains(.bottomTrailing) {
                    parts.append("corner-bottom-right-shape: \(token);")
                }
                if corners.contains(.bottomLeading) {
                    parts.append("corner-bottom-left-shape: \(token);")
                }
            }
        }

        if corners == .all || corners.contains(.topLeading) {
            parts.append("--cr-tl: \(r);")
        }
        if corners == .all || corners.contains(.topTrailing) {
            parts.append("--cr-tr: \(r);")
        }
        if corners == .all || corners.contains(.bottomTrailing) {
            parts.append("--cr-br: \(r);")
        }
        if corners == .all || corners.contains(.bottomLeading) {
            parts.append("--cr-bl: \(r);")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var cssClass: String? { "corner-radius" }
    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {

    func cornerRadius(_ value: Double) -> some Component {
        style(CornerRadiusStyle(value: value, corners: .all))
    }

    func cornerRadius(_ value: Double, shape: CornerShape) -> some Component {
        style(CornerRadiusStyle(value: value, corners: .all, shape: shape))
    }
    /// Numeric corner radius in spacing units (multiplied by `--space-unit`).
    /// By default this applies to all corners. You can pass a `CornerSet`
    /// to target specific corners (e.g. `.topLeading`, `.bottomTrailing`).
    ///
    /// Examples:
    /// - `cornerRadius(corners: .all, 8)`
    /// - `cornerRadius(corners: .topLeading, 4)`
    func cornerRadius(_ corners: CornerSet = .all, _ value: Double) -> some Component {
        style(CornerRadiusStyle(value: value, corners: corners))
    }

    /// Extended overload that also accepts a desired corner shape. The `shape`
    /// parameter is currently recorded into a custom property (`--cr-shape`)
    /// for future use, but does not affect the rendered CSS yet.
    ///
    /// Examples:
    /// - `cornerRadius(corners: .all, 8, shape: .round)`
    /// - `cornerRadius(corners: .topLeading, 4, shape: .squircle)`
    /// - `cornerRadius(corners: .bottomTrailing, 4, shape: .superellipse(2))`
    func cornerRadius(
        _ corners: CornerSet = .all,
        _ value: Double,
        shape: CornerShape
    ) -> some Component {
        style(CornerRadiusStyle(value: value, corners: corners, shape: shape))
    }
}
