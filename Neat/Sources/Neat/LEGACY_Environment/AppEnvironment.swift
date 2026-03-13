import Foundation

// MARK: - Environment Values

/// A lightweight container for values propagated through the component tree.
/// Values are addressed via `EnvironmentKey` types, similar to SwiftUI’s approach.
public struct AppEnvironmentValues {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: AppEnvironmentKey>(_ key: K.Type) -> K.Value {
        get {
            storage[ObjectIdentifier(key)].flatMap { $0 as? K.Value } ?? K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    /// Merges another set of values into this one, overriding duplicates.
    mutating func merge(_ other: AppEnvironmentValues) {
        for (key, value) in other.storage {
            storage[key] = value
        }
    }
}

// MARK: - Keys

public protocol AppEnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

// MARK: - Property Wrapper

/// Accesses an environment value inside `Component` / `Page` types.
@propertyWrapper
public struct AppEnvironment<Value> {
    private let keyPath: KeyPath<AppEnvironmentValues, Value>

    public init(_ keyPath: KeyPath<AppEnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        guard let context = RenderContext.current else {
            fatalError("Environment accessed outside of a render context.")
        }
        return context.environmentValues[keyPath: keyPath]
    }

    public var projectedValue: AppEnvironment<Value> { self }
}
