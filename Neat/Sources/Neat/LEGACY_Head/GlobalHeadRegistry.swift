import Foundation
#if canImport(Dispatch)
import Dispatch
#endif

/// Stores a single global `<head>` fragment registered by the running `App`.
public final class GlobalHeadRegistry {
    public nonisolated(unsafe) static let shared = GlobalHeadRegistry()

    private var storedHead: AnyHead?
    #if canImport(Dispatch) && !os(WASI)
    private let queue = DispatchQueue(label: "neat.global-head-registry", attributes: .concurrent)
    #endif

    private init() {}

    /// Registers the global head content once per application.
    public func register(head: AnyHead) {
        #if canImport(Dispatch) && !os(WASI)
        queue.async(flags: .barrier) {
            self.storedHead = head
        }
        #else
        storedHead = head
        #endif
    }

    /// Retrieves the registered head fragment, if any.
    public func head() -> AnyHead? {
        #if canImport(Dispatch) && !os(WASI)
        queue.sync { storedHead }
        #else
        storedHead
        #endif
    }

    /// Convenience helper that renders the stored head into an `ElementNode`.
    public func htmlNode(context: RenderContext? = nil) -> ElementNode? {
        head()?.build(in: context)
    }
}
