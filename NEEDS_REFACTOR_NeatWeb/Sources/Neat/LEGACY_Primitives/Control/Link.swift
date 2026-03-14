public struct Link<Label: Component>: _PrimitiveComponent {
    public let destination: any Page.Type
    public let label: Label

    /// Creates a link to a `Page` with a custom label component.
    ///
    /// Example:
    /// ```swift
    /// Link(destination: AboutPage.self) {
    ///     Text("About")
    /// }
    /// ```
    public init(destination: any Page.Type, @ComponentBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public func build(in context: RenderContext?) -> ElementNode {
        let href = context?.environmentValues.router.path(for: destination) ?? "/"
        let attributes: [String: String] = ["href": href]

        let child = label.build(in: context)

        return ElementNode(
            tag: "a",
            attributes: attributes,
            children: [child]
        )
    }
}

extension Link where Label == Untracked<Text> {
    /// Convenience initializer for simple text links.
    ///
    /// Example:
    /// ```swift
    /// Link(text: "Home", destination: HomePage.self)
    /// ```
    public init(_ text: String, destination: any Page.Type) {
        self.destination = destination
        self.label = Untracked(Text(text))
    }
}
