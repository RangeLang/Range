public struct Route: RouteComponent {
    let path: [RoutePathComponent]
    let pageType: (any Page.Type)?
    let makePage: (() -> any Page)?
    let children: AnyRoute?

    public init<P: Page>(_ path: String, _ page: P.Type) {
        self.path = path.routePathComponents
        self.pageType = page
        self.makePage = { P() }
        self.children = nil
    }

    public init(_ path: String, @RouteBuilder children: () -> AnyRoute) {
        self.path = path.routePathComponents
        self.pageType = nil
        self.makePage = nil
        self.children = children()
    }

    public init<P: Page>(_ path: String, _ page: P.Type, @RouteBuilder children: () -> AnyRoute) {
        self.path = path.routePathComponents
        self.pageType = page
        self.makePage = { P() }
        self.children = children()
    }

    public func build() -> [RouteNode] {
        let childNodes = children?.build() ?? []
        return [
            RouteNode(
                path: path,
                pageType: pageType,
                makePage: makePage,
                children: childNodes
            )
        ]
    }
}
