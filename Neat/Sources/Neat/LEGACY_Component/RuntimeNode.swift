public final class RuntimeNode: @unchecked Sendable {
    private nonisolated(unsafe) static var nextID: Int32 = 0

    public let id: Int32
    public var key: AnyHashable?
    public var componentType: Any.Type
    public var stateSlots: [Any?] = []
    public var children: [RuntimeNode] = []
    public var elementTree: ElementNode?

    public init(componentType: Any.Type, key: AnyHashable?) {
        self.id = RuntimeNode.makeID()
        self.componentType = componentType
        self.key = key
    }

    public func state<Value>(slot: Int, default value: Value) -> Value {
        ensureCapacity(for: slot)
        if let stored = stateSlots[slot] as? Value {
            return stored
        }
        stateSlots[slot] = value
        return value
    }

    public func setState<Value>(slot: Int, value: Value) {
        ensureCapacity(for: slot)
        stateSlots[slot] = value
    }

    private func ensureCapacity(for slot: Int) {
        if slot < stateSlots.count {
            return
        }
        stateSlots.append(contentsOf: repeatElement(nil, count: slot + 1 - stateSlots.count))
    }

    private static func makeID() -> Int32 {
        let id = nextID
        nextID &+= 1
        return id
    }
}
