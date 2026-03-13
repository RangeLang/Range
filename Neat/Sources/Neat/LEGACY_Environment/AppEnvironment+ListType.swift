private enum ListTypeEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: ListType { .unordered }
}

public extension AppEnvironmentValues {
    var listType: ListType {
        get { self[ListTypeEnvironmentKey.self] }
        set { self[ListTypeEnvironmentKey.self] = newValue }
    }
}
