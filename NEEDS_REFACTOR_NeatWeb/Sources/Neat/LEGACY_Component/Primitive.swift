import Foundation

/// A helper for building primitive components that need consistent identity and event handling
/// across Server (SSR/Hydration) and Client (WASM) environments.
public struct PrimitiveContext {
    public let id: String?
    public let index: Int32
    public let attributes: [String: String]

    /// Prepares a primitive for rendering, handling all platform-specific registration.
    ///
    /// - Parameters:
    ///   - context: The current RenderContext.
    ///   - name: The primitive component name (e.g., "Button").
    ///   - typeName: The full type name (e.g., "Button<Text>").
    ///   - event: The event to register (e.g., "click"), if any.
    ///   - action: The action to execute when the event fires (WASI only).
    /// - Returns: A `PrimitiveContext` containing the necessary ID and attributes.
    public static func prepare(
        in context: RenderContext?,
        name: String,
        typeName: String? = nil,
        event: String? = nil,
        action: (() -> Void)? = nil
    ) -> PrimitiveContext? {
        guard let context = context else { return nil }

        var attributes: [String: String] = [:]

        // Mark this primitive as used (for SSR asset tracking)
        context.registerPrimitiveUse(name)

        // 1. Generate sequential numeric ID (agreed upon by both sides)
        let idx = context.nextNodeIndex()

        // 2. Register event handler if provided (WASM registry)
        if let action = action, context.isTracking {
            #if os(WASI)
            let wrapped = {
                print("[neat-wasm] action", idx)
                action()
            }
            WasmEventRegistry.shared.register(id: idx, handler: wrapped)
            #else
            WasmEventRegistry.shared.register(id: idx, handler: action)
            #endif
        }

        // 3. Set attribute for VDOM diffing and event targeting
        attributes["data-neat-idx"] = String(idx)

        if let typeName {
            attributes["data-neat-component"] = typeName
        }
        if let event {
            attributes["data-neat-event"] = event
        }

        return PrimitiveContext(id: nil, index: idx, attributes: attributes)
    }
}
