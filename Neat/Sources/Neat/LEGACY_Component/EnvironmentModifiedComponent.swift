public struct EnvironmentModifiedComponent<Base: Component>: _PrimitiveComponent {

    public var base: Base
    fileprivate let overrides: [(inout AppEnvironmentValues) -> Void]

    public init(
        base: Base,
        apply: @escaping (inout AppEnvironmentValues) -> Void
    ) {
        self.base = base
        self.overrides = [apply]
    }

    fileprivate init(
        base: Base,
        overrides: [(inout AppEnvironmentValues) -> Void]
    ) {
        self.base = base
        self.overrides = overrides
    }

    public func build(in context: RenderContext?) -> ElementNode {
        // If there's no build context, we can't modify the environment;
        // just build the base component as-is.
        guard let ctx = context else {
            return base.build(in: nil)
        }

        // Snapshot current environment, apply modification for the subtree,
        // then restore the previous values after building.
        let previous = ctx.environmentValues
        var modified = previous
        for apply in overrides {
            apply(&modified)
        }
        ctx.environmentValues = modified
        defer { ctx.environmentValues = previous }

        return base.build(in: ctx)
    }
}

public protocol _EnvironmentOverrideMerging {
    associatedtype Merged: Component
    func _appendingEnvironmentOverride(
        _ apply: @escaping (inout AppEnvironmentValues) -> Void
    ) -> Merged
}

extension EnvironmentModifiedComponent: _EnvironmentOverrideMerging {
    public func _appendingEnvironmentOverride(
        _ apply: @escaping (inout AppEnvironmentValues) -> Void
    ) -> EnvironmentModifiedComponent<Base> {
        EnvironmentModifiedComponent(base: base, overrides: overrides + [apply])
    }
}

public extension Component {
    func environment<Value>(
        _ keyPath: WritableKeyPath<AppEnvironmentValues, Value>,
        _ value: Value
    ) -> some Component {
        EnvironmentModifiedComponent(base: self) { env in
            env[keyPath: keyPath] = value
        }
    }
}

public extension Component where Self: _EnvironmentOverrideMerging {
    func environment<Value>(
        _ keyPath: WritableKeyPath<AppEnvironmentValues, Value>,
        _ value: Value
    ) -> some Component {
        _appendingEnvironmentOverride { env in
            env[keyPath: keyPath] = value
        }
    }
}

extension EnvironmentModifiedComponent: _StyleForwardingComponent where Base: _StyleForwardingComponent {
    func _buildForwardingStyles(
        _ styles: [any StyleModifier],
        in context: RenderContext?
    ) -> ElementNode {
        guard let ctx = context else {
            return base._buildForwardingStyles(styles, in: nil)
        }

        let previous = ctx.environmentValues
        var modified = previous
        for apply in overrides {
            apply(&modified)
        }
        ctx.environmentValues = modified
        defer { ctx.environmentValues = previous }

        return base._buildForwardingStyles(styles, in: ctx)
    }
}
