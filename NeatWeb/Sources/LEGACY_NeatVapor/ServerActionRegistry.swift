import Vapor

/// A single place where `@ServerAction`-annotated methods can register
/// their server-side handlers. This keeps the macro-generated wiring
/// code decoupled from Vapor's router configuration.
///
/// The expected flow is:
/// 1. Each `@ServerAction` expansion generates a static registration thunk,
///    e.g. `__serverAction_<name>Registration`, that calls
///    `ServerActionRegistry.shared.register(...)`.
/// 2. During application boot, `configure(_:for:)` calls
///    `ServerActionRegistry.shared.registerAll(on:)`.
/// 3. All registered actions are bound to Vapor's `Application` under their
///    configured paths and HTTP methods.
public final class ServerActionRegistry: @unchecked Sendable {

    /// Shared global instance used by macro-generated registration thunks.
    nonisolated(unsafe) public static let shared = ServerActionRegistry()

    /// Represents a single server action endpoint.
    public struct Action {
        /// HTTP method to use when registering the route.
        public enum Method {
            case get
            case post
            case put
            case delete

            /// Maps the enum to Vapor's HTTP method.
            fileprivate var http: HTTPMethod {
                switch self {
                case .get: return .GET
                case .post: return .POST
                case .put: return .PUT
                case .delete: return .DELETE
                }
            }
        }

        /// The URL path this action will be exposed at, e.g.
        /// `/__neat/actions/home-page/getResponse`.
        public let path: String

        /// The HTTP method to use for this action.
        public let method: Method

        /// The underlying handler that Vapor will invoke when this action's
        /// route is hit.
        ///
        /// The handler is responsible for decoding any payload from the
        /// request and encoding the response body.
        public let handler: (Request) async throws -> Response

        public init(
            path: String,
            method: Method,
            handler: @escaping (Request) async throws -> Response
        ) {
            self.path = path
            self.method = method
            self.handler = handler
        }
    }

    // MARK: - Storage

    private var actions: [Action] = []
    private let lock = Lock()

    private init() {}

    // MARK: - Registration API

    /// Registers a new server action. This is intended to be called from
    /// macro-generated static thunks on the owning type.
    ///
    /// - Parameters:
    ///   - path:   The route path to mount this action at.
    ///   - method: The HTTP method to use when registering the route.
    ///   - handler: A Vapor-compatible handler that produces a `Response`.
    public func register(
        path: String,
        method: Action.Method,
        handler: @escaping (Request) async throws -> Response
    ) {
        lock.withLock {
            actions.append(Action(path: path, method: method, handler: handler))
        }
    }

    /// Binds all previously registered actions to the given Vapor
    /// application. This should be called once during application boot,
    /// typically from the global `configure(_:for:)` function.
    ///
    /// It is safe to call this multiple times, but doing so will install
    /// duplicate routes; consumers should ensure they only invoke this once.
    public func registerAll(on app: Application) {
        let snapshot = lock.withLock { actions }

        for action in snapshot {
            // Split the stored path into Vapor `PathComponent`s so that
            // we can support segments like "/foo/bar" without treating
            // the entire string as a single constant.
            let trimmed = action.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let segments =
                trimmed.isEmpty
                ? [PathComponent.constant("")]
                : trimmed.split(separator: "/").map { PathComponent.constant(String($0)) }

            switch action.method {
            case .get:
                app.on(.GET, segments, use: action.handler)
            case .post:
                app.on(.POST, segments, use: action.handler)
            case .put:
                app.on(.PUT, segments, use: action.handler)
            case .delete:
                app.on(.DELETE, segments, use: action.handler)
            }
        }
    }
}

// MARK: - Simple mutual exclusion helper

/// Tiny wrapper around a lock to keep `ServerActionRegistry` thread-safe
/// without exposing synchronization primitives to callers.
private final class Lock {
    private var _lock = NSLock()

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        _lock.lock()
        defer { _lock.unlock() }
        return try body()
    }
}
