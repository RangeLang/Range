/// An internal `RouteComponent` that holds an array of child routes.
internal struct RouteFragment: RouteComponent {
    let children: [AnyRoute]

    init(_ children: [AnyRoute]) {
        self.children = children
    }

    func build() -> [RouteNode] {
        children.flatMap { $0.build() }
    }
}
