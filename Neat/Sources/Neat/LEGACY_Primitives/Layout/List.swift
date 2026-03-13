public struct List<Data: Collection, ID: Hashable, RowContent: Component>: _PrimitiveComponent {
    public let data: Data
    private let id: (Data.Element) -> ID
    private let content: (Data.Element) -> RowContent

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ComponentBuilder content: @escaping (Data.Element) -> RowContent
    ) {
        self.data = data
        self.id = { $0[keyPath: id] }
        self.content = content
    }

    public init(
        _ data: Data,
        id: @escaping (Data.Element) -> ID,
        @ComponentBuilder content: @escaping (Data.Element) -> RowContent
    ) {
        self.data = data
        self.id = id
        self.content = content
    }

    public func build(in context: RenderContext?) -> ElementNode {
        if let context {
            context.registerPrimitiveUse(Self.componentName)
        }

        return ScrollArea(axis: .vertical) {
            ListItems(
                data: data,
                id: id,
                content: content
            )
        }
        .frame(width: .fill)
        .build(in: context)
    }

}

public extension List where Data.Element: Identifiable, ID == Data.Element.ID {
    init(
        _ data: Data,
        @ComponentBuilder content: @escaping (Data.Element) -> RowContent
    ) {
        self.init(data, id: \.id, content: content)
    }
}

private struct ListItems<Data: Collection, ID: Hashable, RowContent: Component>: _PrimitiveComponent {
    let data: Data
    let id: (Data.Element) -> ID
    let content: (Data.Element) -> RowContent

    func build(in context: RenderContext?) -> ElementNode {
        let listType = context?.environmentValues.listType ?? .unordered
        let spacing = context?.environmentValues.listRowSpacing
        let items = data.map { element in
            _ = id(element)
            return ElementNode(
                tag: "li",
                classes: ["list-item"],
                children: [content(element).build(in: context)]
            )
        }

        var styles: [String: StyleValue] = [:]
        if let spacing {
            styles["--list-row-gap"] = StyleValue(value: "calc(\(spacing) * var(--space-unit))", priority: 0)
        }
        return ElementNode(
            tag: listType == .ordered ? "ol" : "ul",
            classes: ["list"],
            styleValues: styles,
            children: items
        )
    }
}
