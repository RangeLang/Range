public protocol _PrimitiveComponent: Component where Body == Never {
    /// Canonical primitive name used by the runtime and macro layers.
    ///
    /// The default implementation derives this from `Self`'s type name by
    /// stripping the module prefix and any generic arguments.
    static var primitiveName: String { get }
}

public extension _PrimitiveComponent {
    var body: Never {
        fatalError("Primitive components do not have a body.")
    }

    /// Default primitive name derived from the conforming type's name by
    /// stripping module prefix and generic arguments.
    static var primitiveName: String {
        #if os(WASI)
        return "primitive"
        #else
        let full = String(describing: Self.self)
        let noModule = full.split(separator: ".").last.map(String.init) ?? full
        let base = noModule.split(separator: "<").first.map(String.init) ?? noModule
        return base
        #endif
    }

    /// Ensure primitives register under a generic-stripped name.
    static var typeName: String { primitiveName }
}
