private enum ToggleStyleEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: AnyToggleStyle { .checkbox }
}

extension AppEnvironmentValues {
    var toggleStyle: AnyToggleStyle {
        get { self[ToggleStyleEnvironmentKey.self] }
        set { self[ToggleStyleEnvironmentKey.self] = newValue }
    }
}
