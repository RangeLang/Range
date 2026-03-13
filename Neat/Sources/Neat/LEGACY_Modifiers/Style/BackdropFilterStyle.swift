public struct BackdropFilterStyle: StyleModifier {
    public let effects: [FilterEffect]

    public init(effects: [FilterEffect]) {
        self.effects = effects
    }

    public var cssStyle: String? {
        guard !effects.isEmpty else { return nil }
        let value = effects.map(\.cssValue).joined(separator: " ")
        return "backdrop-filter: \(value)"
    }

    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    func backdropFilter(_ effects: FilterEffect...) -> some Component {
        style(BackdropFilterStyle(effects: effects))
    }

    func backdropFilter(_ build: (inout FilterChain) -> Void) -> some Component {
        var chain = FilterChain()
        build(&chain)
        return style(BackdropFilterStyle(effects: chain.effects))
    }
}
