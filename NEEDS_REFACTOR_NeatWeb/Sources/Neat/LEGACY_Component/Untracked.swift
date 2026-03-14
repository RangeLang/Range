
public struct Untracked<Content: Component>: _PrimitiveComponent {
    public let content: Content

    public init(_ content: Content) {
        self.content = content
    }

    public func build(in context: RenderContext?) -> ElementNode {
        // Render the component without passing the context,
        // effectively disabling tracking/hydration for this subtree.
        content.build(in: nil)
    }
}
