import Foundation

private enum TextTagEnvironmentKey: AppEnvironmentKey {
    static var defaultValue: TextTag { .span }
}

public extension AppEnvironmentValues {
    /// Default text tag used by `Text` when no explicit override is provided.
    var textTag: TextTag {
        get { self[TextTagEnvironmentKey.self] }
        set { self[TextTagEnvironmentKey.self] = newValue }
    }
}
