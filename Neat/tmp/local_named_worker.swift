import Foundation

// Backend implementation for NeatCore's Promise and Logger surface.
// NeatCore declares the language-visible API; Swift runtime support lives here.
enum PromiseRuntimeState<Success, Failure> {
    case loading
    case success(Success)
    case failure(Failure)
}

final class Promise<Success: Sendable, Failure>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: PromiseRuntimeState<Success, Failure>

    private init(state: PromiseRuntimeState<Success, Failure>) {
        self.state = state
    }

    static func loading() -> Promise<Success, Failure> {
        Promise(state: .loading)
    }

    static func success(_ value: Success) -> Promise<Success, Failure> {
        Promise(state: .success(value))
    }

    static func failure(_ error: Failure) -> Promise<Success, Failure> {
        Promise(state: .failure(error))
    }

    func snapshot() -> PromiseRuntimeState<Success, Failure> {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func isLoading() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .loading = state {
            return true
        }
        return false
    }

    func value() -> Success? {
        lock.lock()
        defer { lock.unlock() }
        if case .success(let value) = state {
            return value
        }
        return nil
    }

    func error() -> Failure? {
        lock.lock()
        defer { lock.unlock() }
        if case .failure(let error) = state {
            return error
        }
        return nil
    }

    func resolveSuccess(_ value: Success) {
        lock.lock()
        state = .success(value)
        lock.unlock()
    }

    func resolveFailure(_ error: Failure) {
        lock.lock()
        state = .failure(error)
        lock.unlock()
    }
}

func settle<Success, Failure>(_ result: Result<Success, Failure>) -> Result<Success, Failure> {
    result
}

func settle<Success: Sendable, Failure>(_ promise: Promise<Success, Failure>) -> Result<Success, Failure> {
    while true {
        switch promise.snapshot() {
        case .loading:
            Thread.sleep(forTimeInterval: 0.001)
        case .success(let value):
            return .success(value)
        case .failure(let error):
            return .failure(error)
        }
    }
}

enum Logger {
    static func log(_ value: Any) {
        print(String(describing: value))
    }

    static func debug(_ value: Any) {
        print(String(describing: value))
    }

    static func info(_ value: Any) {
        print(String(describing: value))
    }

    static func success(_ value: Any) {
        print(String(describing: value))
    }

    static func warning(_ value: Any) {
        print(String(describing: value))
    }

    static func error(_ value: Any) {
        fputs("\(String(describing: value))\n", stderr)
    }
}

enum FetchError {
    case missing
    case network
}

func usePromise(request: Promise<String, FetchError>) {
    Logger.info("local promise typed")
}

func useResult(result: Result<String, FetchError>) {
    Logger.info("local result typed")
}

func loadUser(id: Int) {
    func fetchLocal(userID: Int) -> Promise<String, FetchError> {
        let promise = Promise<String, FetchError>.loading()
        Task {
            let value: String = {
                    if userID == 0 {
                        return "system"
                    }
                    return "george"
            }()
            promise.resolveSuccess(value)
        }
        return promise
    }
    var liveRequest: Promise<String, FetchError> = fetchLocal(userID: id)
    usePromise(request: liveRequest)
    Logger.info("local worker request started")
    let settledResult: Result<String, FetchError> = settle(fetchLocal(userID: id))
    useResult(result: settledResult)
    Logger.info("local worker request finished")
}

@main
struct NeatMain {
    static func main() throws {
        loadUser(id: 1)
    }
}
