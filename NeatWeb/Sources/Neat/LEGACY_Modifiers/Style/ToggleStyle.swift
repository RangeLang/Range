public struct ToggleStyleConfiguration {
    public let isOn: Bool
    public let toggle: AnyComponent

    public init(isOn: Bool, toggle: AnyComponent) {
        self.isOn = isOn
        self.toggle = toggle
    }
}

public struct AnyToggleStyle {
    private let _makeBody: (ToggleStyleConfiguration) -> AnyComponent

    public init<S: ToggleStyle>(_ style: S) {
        self._makeBody = { configuration in
            AnyComponent(style.makeBody(configuration: configuration))
        }
    }

    public func makeBody(configuration: ToggleStyleConfiguration) -> AnyComponent {
        _makeBody(configuration)
    }
}

public protocol ToggleStyle {
    associatedtype Body: Component

    func makeBody(configuration: ToggleStyleConfiguration) -> Body
}

public struct SwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: ToggleStyleConfiguration) -> some Component {
        configuration.toggle
            .frame(width: .px(42), height: .px(22))
            .cornerRadius(5000)
            .backgroundColor(configuration.isOn ? .black : .gray.opacity(0.35))
            .padding(1)
    }
}

public struct CheckboxToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: ToggleStyleConfiguration) -> some Component {
        configuration.toggle
            .frame(width: .px(18), height: .px(18))
            .cornerRadius(3)
            .backgroundColor(configuration.isOn ? .black : .gray.opacity(0.25))
    }
}

public extension AnyToggleStyle {
    static var checkbox: AnyToggleStyle { AnyToggleStyle(CheckboxToggleStyle()) }
    static var `switch`: AnyToggleStyle { AnyToggleStyle(SwitchToggleStyle()) }
}

public extension Component {
    func toggleStyle<S: ToggleStyle>(_ style: S) -> some Component {
        environment(\.toggleStyle, AnyToggleStyle(style))
    }

    func toggleStyle(_ style: AnyToggleStyle) -> some Component {
        environment(\.toggleStyle, style)
    }
}

public extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

public extension ToggleStyle where Self == SwitchToggleStyle {
    static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}
