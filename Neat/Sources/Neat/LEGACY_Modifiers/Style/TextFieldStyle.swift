public struct TextFieldStyleConfiguration {
    public let textField: AnyComponent

    public init(textField: AnyComponent) {
        self.textField = textField
    }
}

public struct AnyTextFieldStyle {
    private let _makeBody: (TextFieldStyleConfiguration) -> AnyComponent

    public init<S: TextFieldStyle>(_ style: S) {
        self._makeBody = { configuration in
            AnyComponent(style.makeBody(configuration: configuration))
        }
    }

    public func makeBody(configuration: TextFieldStyleConfiguration) -> AnyComponent {
        _makeBody(configuration)
    }
}

public protocol TextFieldStyle {
    associatedtype Body: Component

    func makeBody(configuration: TextFieldStyleConfiguration) -> Body
}

public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}

    public func makeBody(configuration: TextFieldStyleConfiguration) -> some Component {
        configuration.textField
    }
}

public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}

    public func makeBody(configuration: TextFieldStyleConfiguration) -> some Component {
        configuration.textField
            .padding(.vertical, 1)
            .padding(.horizontal, 2)
            .backgroundColor(.white)
            .border(.black, width: 1)
            .cornerRadius(10)
    }
}

public extension AnyTextFieldStyle {
    static var plain: AnyTextFieldStyle { AnyTextFieldStyle(PlainTextFieldStyle()) }
    static var `default`: AnyTextFieldStyle { AnyTextFieldStyle(DefaultTextFieldStyle()) }
}

public extension Component {
    func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some Component {
        environment(\.textFieldStyle, AnyTextFieldStyle(style))
    }

    func textFieldStyle(_ style: AnyTextFieldStyle) -> some Component {
        environment(\.textFieldStyle, style)
    }
}

public extension TextFieldStyle where Self == PlainTextFieldStyle {
    static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

public extension TextFieldStyle where Self == DefaultTextFieldStyle {
    static var `default`: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}
