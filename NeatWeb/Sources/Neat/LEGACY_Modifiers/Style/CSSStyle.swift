public struct CSSStyle: StyleModifier {
    public let css: String
    public init(css: String) { self.css = css }
    public var cssStyle: String? { css }
    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    // Raw CSS escape hatch as a dedicated style method
    func cssStyle(_ css: String) -> some Component { style(CSSStyle(css: css)) }
}
