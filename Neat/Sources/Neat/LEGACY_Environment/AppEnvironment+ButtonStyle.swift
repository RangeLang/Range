private enum ButtonStyleEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: AnyButtonStyle { .plain }
}

extension AppEnvironmentValues {
    var buttonStyle: AnyButtonStyle {
        get { self[ButtonStyleEnvironmentKey.self] }
        set { self[ButtonStyleEnvironmentKey.self] = newValue }
    }
}
