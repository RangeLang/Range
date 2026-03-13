public struct BackgroundColorStyle: StyleModifier {
    public let color: Color
    public init(color: Color) { self.color = color }
    public var cssStyle: String? {
        "--bg: \(color.cssValue);"
    }
    public var cssClass: String? { "bg-color" }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    func backgroundColor(_ color: Color) -> some Component { style(BackgroundColorStyle(color: color)) }
}
