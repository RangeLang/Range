// A modifier that contributes attributes to the component's opening HTML tag
public protocol OpenTagModifier: ComponentModifier {
    // CSS declaration string to append to the opening tag's style attribute
    // Example: "padding: 8px" or "background-color: red"
    var cssStyle: String? { get }
    // Single CSS class name to append to class attribute
    var cssClass: String? { get }
    // Additional attributes (name, value) to inject into the opening tag
    var extraAttributes: [(name: String, value: String)] { get }

    /// Optional utility rule that describes a reusable CSS class + declaration
    /// that can be emitted into an external stylesheet.
    var utilityRule: (name: String, declaration: String)? { get }

    /// Whether this modifier requires the component wrapper to participate in layout
    /// (i.e. overrides the default `display: contents` host).
    var requiresLayoutBox: Bool { get }
}

public extension OpenTagModifier {
    var utilityRule: (name: String, declaration: String)? { nil }
    var requiresLayoutBox: Bool { true }
}
