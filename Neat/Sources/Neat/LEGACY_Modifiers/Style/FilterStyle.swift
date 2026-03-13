public enum FilterEffect {
    case blur(Int)
    case brightness(Int)
    case contrast(Int)
    case grayscale(Int)
    case hueRotate(Int)
    case invert(Int)
    case opacity(Int)
    case saturate(Int)
    case sepia(Int)
    case dropShadow(offset: Offset, blur: Int, color: Color)

    var cssValue: String {
        switch self {
        case .blur(let radius):
            return "blur(\(radius)px)"
        case .brightness(let percent):
            return "brightness(\(percent)%)"
        case .contrast(let percent):
            return "contrast(\(percent)%)"
        case .grayscale(let percent):
            return "grayscale(\(percent)%)"
        case .hueRotate(let degrees):
            return "hue-rotate(\(degrees)deg)"
        case .invert(let percent):
            return "invert(\(percent)%)"
        case .opacity(let percent):
            return "opacity(\(percent)%)"
        case .saturate(let percent):
            return "saturate(\(percent)%)"
        case .sepia(let percent):
            return "sepia(\(percent)%)"
        case .dropShadow(let offset, let blur, let color):
            return "drop-shadow(\(offset.x)px \(offset.y)px \(blur)px \(color.cssValue))"
        }
    }
}

public struct FilterChain {
    var effects: [FilterEffect] = []

    @discardableResult
    public mutating func blur(_ radius: Int) -> FilterChain {
        effects.append(.blur(radius))
        return self
    }

    @discardableResult
    public mutating func brightness(_ percent: Int) -> FilterChain {
        effects.append(.brightness(percent))
        return self
    }

    @discardableResult
    public mutating func contrast(_ percent: Int) -> FilterChain {
        effects.append(.contrast(percent))
        return self
    }

    @discardableResult
    public mutating func grayscale(_ percent: Int) -> FilterChain {
        effects.append(.grayscale(percent))
        return self
    }

    @discardableResult
    public mutating func hueRotate(_ degrees: Int) -> FilterChain {
        effects.append(.hueRotate(degrees))
        return self
    }

    @discardableResult
    public mutating func invert(_ percent: Int) -> FilterChain {
        effects.append(.invert(percent))
        return self
    }

    @discardableResult
    public mutating func opacity(_ percent: Int) -> FilterChain {
        effects.append(.opacity(percent))
        return self
    }

    @discardableResult
    public mutating func saturate(_ percent: Int) -> FilterChain {
        effects.append(.saturate(percent))
        return self
    }

    @discardableResult
    public mutating func sepia(_ percent: Int) -> FilterChain {
        effects.append(.sepia(percent))
        return self
    }

    @discardableResult
    public mutating func dropShadow(offset: Offset, blur: Int, color: Color) -> FilterChain {
        effects.append(.dropShadow(offset: offset, blur: blur, color: color))
        return self
    }
}

public struct FilterStyle: StyleModifier {
    public let effects: [FilterEffect]

    public init(effects: [FilterEffect]) {
        self.effects = effects
    }

    public var cssStyle: String? {
        guard !effects.isEmpty else { return nil }
        let value = effects.map(\.cssValue).joined(separator: " ")
        return "filter: \(value)"
    }

    public var cssClass: String? { nil }
    public var extraAttributes: [(name: String, value: String)] { [] }
    public var utilityRule: (name: String, declaration: String)? { nil }
}

public extension Component {
    func filter(_ effects: FilterEffect...) -> some Component {
        style(FilterStyle(effects: effects))
    }

    func filter(_ build: (inout FilterChain) -> Void) -> some Component {
        var chain = FilterChain()
        build(&chain)
        return style(FilterStyle(effects: chain.effects))
    }
}
