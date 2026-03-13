public struct LineHeightStyle: StyleModifier {
    /// Unitless multiplier applied to the current font size to determine line height.
    /// For example, a value of `1.0` produces tight lines, while `1.5` adds more
    /// vertical spacing between lines.
    public let value: Double

    public init(_ value: Double) {
        self.value = value
    }

    /// We set the `--lh` custom property; a corresponding `.line-height` utility
    /// in CSS should apply `line-height: var(--lh, 1);` or similar.
    public var cssStyle: String? {
        "--lh: \(value);"
    }

    /// Utility class that applies `line-height: var(--lh, ...)` in global CSS.
    public var cssClass: String? { "line-height" }

    public var extraAttributes: [(name: String, value: String)] { [] }

    public var utilityRule: (name: String, declaration: String)? { nil }


}

public extension Component {
    /// Sets the line-height for this component's root element as a unitless
    /// multiplier. Because `line-height` is inherited in CSS, children will
    /// automatically inherit this value unless they override it.
    ///
    /// Example:
    /// - `.lineHeight(1.0)` for tight lines (good for single headings)
    /// - `.lineHeight(1.5)` for more generous paragraph spacing
    func lineHeight(_ value: Double) -> some Component {
        style(LineHeightStyle(value))
    }
}
