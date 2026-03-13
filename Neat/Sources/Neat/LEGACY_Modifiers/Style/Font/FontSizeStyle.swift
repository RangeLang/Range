public struct FontSizeStyle: StyleModifier {
    /// Raw CSS value to assign to the `--fs` custom property.
    /// This is typically either a token reference like `var(--font-size-body)`
    /// or a literal rem value such as `1.25rem`.
    public let cssValue: String

    /// Designated initializer from a pre-defined `FontSize` token.
    public init(size: FontSize) {
        self.cssValue = size.cssValue
    }

    /// Internal initializer for constructing from an arbitrary CSS value.
    init(cssValue: String) {
        self.cssValue = cssValue
    }

    /// We set the `--fs` custom property; the `.font-size` utility class
    /// in `global.css` reads this to apply `font-size`.
    public var cssStyle: String? {
        "--fs: \(cssValue);"
    }

    /// Utility class that applies `font-size: var(--fs, ...)` in global CSS.
    public var cssClass: String? { "font-size" }

    public var extraAttributes: [(name: String, value: String)] { [] }

    public var utilityRule: (name: String, declaration: String)? { nil }


}

public extension Component {
    /// Sets the font size for this component's root element using a
    /// predefined `FontSize` token.
    ///
    /// Because `font-size` is inheritable in CSS, children will automatically
    /// inherit this size unless they override it.
    func fontSize(_ size: FontSize) -> some Component {
        style(FontSizeStyle(size: size))
    }

    /// Convenience overload that accepts a raw scale value in rem units.
    ///
    /// For example, `fontSize(1.25)` results in `font-size: 1.25rem`
    /// on the component's root element (via the `--fs` custom property).
    func fontSize(_ value: Double) -> some Component {
        style(FontSizeStyle(cssValue: "\(value)rem"))
    }
}
