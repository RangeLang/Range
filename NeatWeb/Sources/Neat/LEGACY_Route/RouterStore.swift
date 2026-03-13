import Foundation

/// Simple shared holder so non-routing layers (e.g., rendering) can access
/// the router that was constructed while configuring the `App`.
public enum RouterStore {
    nonisolated(unsafe) private static var storedRouter: Router = Router()
    private static let lock = NSLock()

    /// Stores the current router instance, replacing any previous value.
    public static func set(_ router: Router) {
        lock.lock()
        storedRouter = router
        lock.unlock()
    }

    /// Returns the router previously set via `set(_:)`.
    public static func current() -> Router {
        lock.lock()
        let value = storedRouter
        lock.unlock()
        return value
    }
}
