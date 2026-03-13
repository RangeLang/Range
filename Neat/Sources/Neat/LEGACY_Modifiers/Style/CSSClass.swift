public struct CSSClass: StyleModifier {
    public let name: String
    public init(name: String) { self.name = name }
    public var cssStyle: String? { nil }
    public var cssClass: String? { name }
    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    // Add a CSS class by name
    func cssClass(_ name: String) -> some Component { style(CSSClass(name: name)) }
}
