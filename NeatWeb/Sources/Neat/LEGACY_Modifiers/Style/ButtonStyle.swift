public struct ButtonStyleConfiguration {
    public let label: AnyComponent

    public init(label: AnyComponent) {
        self.label = label
    }
}

public struct AnyButtonStyle {
    private let _makeBody: (ButtonStyleConfiguration) -> AnyComponent

    public init<S: ButtonStyle>(_ style: S) {
        self._makeBody = { configuration in
            AnyComponent(style.makeBody(configuration: configuration))
        }
    }

    public func makeBody(configuration: ButtonStyleConfiguration) -> AnyComponent {
        _makeBody(configuration)
    }
}

public protocol ButtonStyle {
    associatedtype Body: Component

    func makeBody(configuration: ButtonStyleConfiguration) -> Body
}

public struct PlainButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: ButtonStyleConfiguration) -> some Component {
        configuration.label
    }
}

public struct DefaultButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: ButtonStyleConfiguration) -> some Component {
        configuration.label
            .padding(.vertical, 2.5)
            .padding(.horizontal, 3.5)
            .foregroundColor(.white)
            .backgroundColor(.black)
            .cornerRadius(10)
    }
}

public extension AnyButtonStyle {
    static var plain: AnyButtonStyle { AnyButtonStyle(PlainButtonStyle()) }
    static var `default`: AnyButtonStyle { AnyButtonStyle(DefaultButtonStyle()) }
}

public extension Component {
    func buttonStyle<S: ButtonStyle>(_ style: S) -> some Component {
        environment(\.buttonStyle, AnyButtonStyle(style))
    }

    func buttonStyle(_ style: AnyButtonStyle) -> some Component {
        environment(\.buttonStyle, style)
    }
}

public extension ButtonStyle where Self == PlainButtonStyle {
    static var plain: PlainButtonStyle { PlainButtonStyle() }
}

public extension ButtonStyle where Self == DefaultButtonStyle {
    static var `default`: DefaultButtonStyle { DefaultButtonStyle() }
}
