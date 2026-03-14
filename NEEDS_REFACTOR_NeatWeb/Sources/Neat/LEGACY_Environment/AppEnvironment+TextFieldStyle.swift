private enum TextFieldStyleEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: AnyTextFieldStyle { .plain }
}

extension AppEnvironmentValues {
    var textFieldStyle: AnyTextFieldStyle {
        get { self[TextFieldStyleEnvironmentKey.self] }
        set { self[TextFieldStyleEnvironmentKey.self] = newValue }
    }
}
