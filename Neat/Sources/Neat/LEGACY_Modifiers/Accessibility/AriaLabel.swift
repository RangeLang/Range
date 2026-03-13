// Accessibility modifier adding an aria-label attribute.
public struct AriaLabel: AccessibilityModifier {
    public let value: String
    public init(value: String) { self.value = value }
    public var cssStyle: String? { nil }
    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [("aria-label", value)] }
}

public extension Component {
    func ariaLabel(_ text: String) -> some Component { accessibility(AriaLabel(value: text)) }
}
