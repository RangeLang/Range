import Foundation
#if canImport(Dispatch)
import Dispatch
#endif

/// Stores generated CSS utility rules per component so we can serve them
/// similarly to how hydration scripts are exposed.
public final class ComponentStylesRegistry {
    public nonisolated(unsafe) static let shared = ComponentStylesRegistry()

    private var styles: [String: Set<String>] = [:]
    #if canImport(Dispatch) && !os(WASI)
    private let queue = DispatchQueue(label: "neat.component-styles", attributes: .concurrent)
    #endif

    private init() {}

    /// Registers a CSS rule for the given component name.
    public func register(rule: String, for component: String) {
        #if canImport(Dispatch) && !os(WASI)
        queue.async(flags: .barrier) {
            var set = self.styles[component, default: Set<String>()]
            set.insert(rule)
            self.styles[component] = set
        }
        #else
        var set = styles[component, default: Set<String>()]
        set.insert(rule)
        styles[component] = set
        #endif
    }

    /// Returns the combined CSS for a component, if any rules were registered.
    public func css(for component: String) -> String? {
        #if canImport(Dispatch) && !os(WASI)
        queue.sync {
            guard let rules = styles[component], !rules.isEmpty else { return nil }
            return Minifier.css(rules.sorted().joined(separator: ""))
        }
        #else
        guard let rules = styles[component], !rules.isEmpty else { return nil }
        return Minifier.css(rules.sorted().joined(separator: ""))
        #endif
    }

    /// Quick existence check so pages can avoid emitting empty stylesheet links.
    public func hasStyles(for component: String) -> Bool {
        #if canImport(Dispatch) && !os(WASI)
        queue.sync {
            guard let rules = styles[component] else { return false }
            return !rules.isEmpty
        }
        #else
        guard let rules = styles[component] else { return false }
        return !rules.isEmpty
        #endif
    }

}
