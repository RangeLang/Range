import Foundation

public struct LetterSpacingStyle: StyleModifier {
    /// Unitless value interpreted in `em` units for `letter-spacing`.
    /// For example, `0.05` results in `letter-spacing: 0.05em`.
    public let value: Double

    public init(_ value: Double) {
        self.value = value
    }

    public var cssStyle: String? {
        "--ls: \(value);"
    }

    public var cssClass: String? { "letter-spacing" }

    public var extraAttributes: [(name: String, value: String)] { [] }

    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    /// Sets the `letter-spacing` for this component's root element.
    ///
    /// The provided value is interpreted in `em` units. For example:
    /// - `letterSpacing(0.0)` keeps the default tracking.
    /// - `letterSpacing(0.05)` slightly increases tracking.
    func letterSpacing(_ value: Double) -> some Component {
        style(LetterSpacingStyle(value))
    }
}
