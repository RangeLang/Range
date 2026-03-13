public protocol _Renderable {
    func build(in context: RenderContext?) -> ElementNode
}

public extension _Renderable {
    func build() -> ElementNode {
        build(in: nil)
    }
}

extension Never: _Renderable {
    public func build(in context: RenderContext?) -> ElementNode {
        switch self {}
    }
}
