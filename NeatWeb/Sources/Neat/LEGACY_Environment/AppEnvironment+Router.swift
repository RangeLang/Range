private enum RouterEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: Router { Router() }
}

public extension AppEnvironmentValues {
    var router: Router {
        get { self[RouterEnvironmentKey.self] }
        set { self[RouterEnvironmentKey.self] = newValue }
    }
}
