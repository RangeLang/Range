public final class WasmEventRegistry: @unchecked Sendable {
    public static let shared = WasmEventRegistry()

    private struct Entry {
        let id: Int32
        let handler: () -> Void
    }

    private var entries: [Entry] = []

    private init() {}

    public func register(id: Int32, handler: @escaping () -> Void) {
        #if os(WASI)
        print("[neat-wasm] register handler", id)
        let wrapped = {
            print("[neat-wasm] handler invoke", id)
            handler()
        }
        entries.append(Entry(id: id, handler: wrapped))
        #else
        entries.append(Entry(id: id, handler: handler))
        #endif
    }

    public func handle(id: Int32) -> Bool {
        var index = 0
        while index < entries.count {
            if entries[index].id == id {
                #if os(WASI)
                print("[neat-wasm] handle", id)
                #endif
                entries[index].handler()
                return true
            }
            index += 1
        }
        return false
    }

    public func reset() {
        entries.removeAll(keepingCapacity: true)
    }
}
