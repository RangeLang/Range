

public struct ForegroundColorStyle: StyleModifier {
    public let color: Color
    public init(color: Color) { self.color = color }
    public var cssStyle: String? {
        "--c: \(color.cssValue);"
    }
    public var cssClass: String? { "text-color" }
    public var extraAttributes: [(name: String, value: String)] { [] }
}

public extension Component {
    func foregroundColor(_ color: Color) -> some Component { style(ForegroundColorStyle(color: color)) }
}
