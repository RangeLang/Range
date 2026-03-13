public struct ForEach<Data: Collection, ID: Hashable, Content: Component>: _PrimitiveComponent {
    public let data: Data
    private let id: (Data.Element) -> ID
    private let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ComponentBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = { $0[keyPath: id] }
        self.content = content
    }

    public init(
        _ data: Data,
        id: @escaping (Data.Element) -> ID,
        @ComponentBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.content = content
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let nodes = data.map { element in
            let key = AnyHashable(id(element))
            return IdentityComponent(base: content(element), key: key).build(in: context)
        }
        return .fragment(nodes)
    }
}

public extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    init(
        _ data: Data,
        @ComponentBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, id: \.id, content: content)
    }
}
