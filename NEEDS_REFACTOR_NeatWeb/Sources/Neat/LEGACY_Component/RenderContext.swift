import Foundation
import _Concurrency

public final class RenderContext: @unchecked Sendable {

    #if os(WASI)
        public nonisolated(unsafe) static var current: RenderContext?
    #else
        @TaskLocal
        public static var current: RenderContext?
    #endif

    public var environmentValues = AppEnvironmentValues()

    @discardableResult
    public func withCurrent<T>(_ body: () throws -> T) rethrows -> T {
        #if os(WASI)
            let previous = RenderContext.current
            RenderContext.current = self
            defer { RenderContext.current = previous }
            return try body()
        #else
            return try RenderContext.$current.withValue(self, operation: body)
        #endif
    }

    // MARK: - Component scope

    private struct ComponentFrame {
        let name: String
        let typeName: String?
        let type: Any.Type?
    }

    private var componentStack: [ComponentFrame] = []
    public private(set) var usedComponents: Set<String> = []

    public var currentComponent: String? {
        componentStack.last?.name
    }

    public var currentComponentType: String? {
        componentStack.last?.typeName
    }

    /// The underlying Swift type for the current component frame, when available.
    public var currentComponentSwiftType: Any.Type? {
        componentStack.last?.type
    }
    public var isTracking: Bool = false

    public func pushComponent(_ name: String, typeName: String? = nil, type: Any.Type? = nil) {
        componentStack.append(
            ComponentFrame(
                name: name,
                typeName: typeName,
                type: type
            )
        )
        usedComponents.insert(name)
    }

    public func popComponent() {
        _ = componentStack.popLast()
    }

    private var nodeIndex: Int32 = 0

    // MARK: - Runtime graph

    private struct RuntimeFrame {
        var node: RuntimeNode
        var keyedChildren: [AnyHashable: RuntimeNode]
        var unkeyedChildren: [RuntimeNode]
        var unkeyedIndex: Int
        var nextChildren: [RuntimeNode]
        var stateSlotIndex: Int
    }

    private var runtimeStack: [RuntimeFrame] = []
    private var rootRuntimeNode: RuntimeNode?
    private var pendingKey: AnyHashable?

    public var currentRuntimeNode: RuntimeNode? {
        runtimeStack.last?.node
    }

    // MARK: - CSS Collection (New)

    public func registerStyle(_ style: any StyleModifier) {
        guard let component = currentComponent else { return }
        if let utility = style.utilityRule {
            ComponentStylesRegistry.shared.register(
                rule: ".\(utility.name) { \(utility.declaration) }",
                for: component
            )
        }
    }

    public func registerPrimitiveUse(_ name: String) {
        usedComponents.insert(name)
    }

    public init() {}

    public func nextNodeIndex() -> Int32 {
        let index = nodeIndex
        nodeIndex &+= 1
        return index
    }

    @discardableResult
    public func withRootRuntimeNode<T>(_ node: RuntimeNode, _ body: () throws -> T) rethrows -> T {
        let previous = rootRuntimeNode
        rootRuntimeNode = node
        defer { rootRuntimeNode = previous }
        return try body()
    }

    @discardableResult
    public func withPendingKey<T>(_ key: AnyHashable, _ body: () throws -> T) rethrows -> T {
        let previous = pendingKey
        pendingKey = key
        defer { pendingKey = previous }
        return try body()
    }

    public func consumePendingKey() -> AnyHashable? {
        let key = pendingKey
        pendingKey = nil
        return key
    }

    public func resolveRuntimeNode(type: Any.Type, key: AnyHashable?) -> RuntimeNode {
        if runtimeStack.isEmpty {
            if let root = rootRuntimeNode {
                root.componentType = type
                root.key = key
                return root
            }
            let node = RuntimeNode(componentType: type, key: key)
            rootRuntimeNode = node
            return node
        }

        var frame = runtimeStack.removeLast()
        let node: RuntimeNode
        if let key {
            if let existing = frame.keyedChildren.removeValue(forKey: key),
                existing.componentType == type
            {
                node = existing
            } else {
                node = RuntimeNode(componentType: type, key: key)
            }
        } else {
            if frame.unkeyedIndex < frame.unkeyedChildren.count {
                let candidate = frame.unkeyedChildren[frame.unkeyedIndex]
                frame.unkeyedIndex += 1
                if candidate.componentType == type {
                    node = candidate
                } else {
                    node = RuntimeNode(componentType: type, key: nil)
                }
            } else {
                node = RuntimeNode(componentType: type, key: nil)
            }
        }

        node.componentType = type
        node.key = key
        frame.nextChildren.append(node)
        runtimeStack.append(frame)
        return node
    }

    @discardableResult
    public func withRuntimeNode<T>(_ node: RuntimeNode, _ body: () throws -> T) rethrows -> T {
        var keyed: [AnyHashable: RuntimeNode] = [:]
        var unkeyed: [RuntimeNode] = []
        for child in node.children {
            if let key = child.key {
                keyed[key] = child
            } else {
                unkeyed.append(child)
            }
        }

        runtimeStack.append(
            RuntimeFrame(
                node: node,
                keyedChildren: keyed,
                unkeyedChildren: unkeyed,
                unkeyedIndex: 0,
                nextChildren: [],
                stateSlotIndex: 0
            )
        )

        defer {
            let frame = runtimeStack.removeLast()
            node.children = frame.nextChildren
        }

        return try body()
    }

    public func nextStateSlot() -> Int {
        guard !runtimeStack.isEmpty else { return 0 }
        var frame = runtimeStack.removeLast()
        let slot = frame.stateSlotIndex
        frame.stateSlotIndex += 1
        runtimeStack.append(frame)
        return slot
    }

    @discardableResult
    public func withTracking<T>(_ body: () throws -> T) rethrows -> T {
        let previous = isTracking
        if !previous {
            WasmEventRegistry.shared.reset()
        }
        isTracking = true
        defer { isTracking = previous }
        return try body()
    }

}
