public struct ZIndexStyle: StyleModifier {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public var cssStyle: String? {
        "--z: \(value)"
    }

    public var cssClass: String? { "z-index" }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    func zIndex(_ value: Int) -> some Component {
        style(ZIndexStyle(value))
    }
}
