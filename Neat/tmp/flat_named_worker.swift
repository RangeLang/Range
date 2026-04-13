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

func workerA(count: Int) -> Promise<String, String> {
    let promise = Promise<String, String>.loading()
    Task {
        let value: String = {
                if count == 0 {
                    return "zero"
                }
                return "done"
        }()
        promise.resolveSuccess(value)
    }
    return promise
}

@main
struct NeatMain {
    static func main() throws {
        let promise: Promise<String, String> = workerA(count: 2)
        Logger.info("started named worker")
    }
}
