/// A lightweight reverse router that records page types and their fully-qualified paths.
/// It also tracks a stack of prefixed path components so nested `Route` declarations
/// automatically inherit their parents' URL fragments.
public final class Router {
    private struct RouteEntry {
        let typeID: ObjectIdentifier
        let make: () -> any Page
    }

    private var storage: [ObjectIdentifier: String] = [:]
    private var routeEntries: [RouteEntry] = []
    private var routeIndexByID: [ObjectIdentifier: Int] = [:]
    private var prefixStack: [[RoutePathComponent]] = [[]]

    public init() {}

    // MARK: - Prefix management

    public func pushPrefix(_ components: [RoutePathComponent]) {
        let current = prefixStack.last ?? []
        prefixStack.append(current + components)
    }

    public func popPrefix() {
        guard prefixStack.count > 1 else { return }
        prefixStack.removeLast()
    }

    private func fullPath(for components: [RoutePathComponent]) -> String {
        let merged = (prefixStack.last ?? []) + components
        guard !merged.isEmpty else { return "/" }
        let joined = merged.map(\.description).joined(separator: "/")
        return "/\(joined)"
    }

    // MARK: - Route storage

    internal func store(path: [RoutePathComponent], for page: any Page.Type, makePage: @escaping () -> any Page) {
        let id = ObjectIdentifier(page)
        storage[id] = fullPath(for: path)
        if routeIndexByID[id] == nil {
            routeIndexByID[id] = routeEntries.count
            routeEntries.append(RouteEntry(typeID: id, make: makePage))
        }
    }

    internal func store(path: String, for page: any Page.Type, makePage: @escaping () -> any Page) {
        store(path: path.routePathComponents, for: page, makePage: makePage)
    }

    public func path<P: Page>(for page: P.Type) -> String? {
        path(for: ObjectIdentifier(page))
    }

    public func path(for page: any Page.Type) -> String? {
        path(for: ObjectIdentifier(page))
    }

    public func path(for identifier: ObjectIdentifier) -> String? {
        storage[identifier]
    }

    public func routeIndex(for page: any Page.Type) -> Int? {
        routeIndexByID[ObjectIdentifier(page)]
    }

    public func pageFactory(for index: Int) -> (() -> any Page)? {
        guard routeEntries.indices.contains(index) else { return nil }
        return routeEntries[index].make
    }

    public func firstPageFactory() -> (() -> any Page)? {
        routeEntries.first?.make
    }
}

public enum RouterBuilder {
    public static func build(from routes: AnyRoute) -> Router {
        build(from: routes.build())
    }

    public static func build(from nodes: [RouteNode]) -> Router {
        let router = Router()
        populate(router, nodes: nodes, prefix: [])
        return router
    }

    private static func populate(
        _ router: Router,
        nodes: [RouteNode],
        prefix: [RoutePathComponent]
    ) {
        for node in nodes {
            let currentPath = prefix + node.path
            if let pageType = node.pageType, let makePage = node.makePage {
                router.store(path: currentPath, for: pageType, makePage: makePage)
            }
            if !node.children.isEmpty {
                populate(router, nodes: node.children, prefix: currentPath)
            }
        }
    }
}
