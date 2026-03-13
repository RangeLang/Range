private enum ListRowSpacingEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: Double? { nil }
}

public extension AppEnvironmentValues {
    var listRowSpacing: Double? {
        get { self[ListRowSpacingEnvironmentKey.self] }
        set { self[ListRowSpacingEnvironmentKey.self] = newValue }
    }
}
