public struct IdentityComponent<Base: Component>: _PrimitiveComponent {
    public let base: Base
    public let key: AnyHashable

    public init(base: Base, key: AnyHashable) {
        self.base = base
        self.key = key
    }

    public func build(in context: RenderContext?) -> ElementNode {
        guard let context else {
            return base.build(in: context)
        }
        return context.withPendingKey(key) {
            base.build(in: context)
        }
    }
}

public extension Component {
    func id<ID: Hashable>(_ id: ID) -> some Component {
        IdentityComponent(base: self, key: AnyHashable(id))
    }
}
