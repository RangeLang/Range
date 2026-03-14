public struct FontWeightStyle: StyleModifier {
    public let weight: FontWeight

    public init(_ weight: FontWeight) {
        self.weight = weight
    }

    /// We set the `--fw` custom property; the `.font-weight` utility class
    /// in `global.css` reads this to apply `font-weight`.
    ///
    /// global.css:
    /// .font-weight {
    ///     font-weight: var(--fw, var(--font-weight-regular, 400));
    /// }
    public var cssStyle: String? {
        "--fw: \(weight.cssValue);"
    }

    /// Utility class that applies `font-weight: var(--fw, ...) in global CSS.
    public var cssClass: String? { "font-weight" }

    public var extraAttributes: [(name: String, value: String)] { [] }
}

/// Raw numeric font-weight style (e.g. "font-weight: 550") used by
/// the `fontWeight(_ value: Double)` overload.
struct RawFontWeightStyle: StyleModifier {
    let value: Double

    var cssStyle: String? {
        "font-weight: \(value)"
    }

    var cssClass: String? { nil }

    var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    /// Sets the font weight for this component's root element using a
    /// predefined `FontWeight` token. Because `font-weight` is inherited
    /// in CSS, children will automatically inherit this value unless they
    /// override it.
    func fontWeight(_ weight: FontWeight) -> some Component {
        style(FontWeightStyle(weight))
    }

    /// Convenience overload that accepts a raw numeric CSS font-weight value.
    /// For example, `fontWeight(550)` results in `font-weight: 550` on the
    /// component's root element.
    func fontWeight(_ value: Double) -> some Component {
        style(RawFontWeightStyle(value: value))
    }
}
