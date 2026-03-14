import Neat
import Vapor

enum VaporRouteRegistrar {
    static func register(_ nodes: [RouteNode], on routes: RoutesBuilder) {
        for node in nodes {
            let pathComponents = vaporPathComponents(from: node.path)
            if let makePage = node.makePage {
                routes.get(pathComponents, use: pageHandler(makePage: makePage))
            }

            guard !node.children.isEmpty else { continue }

            if pathComponents.isEmpty {
                register(node.children, on: routes)
            } else {
                let group = routes.grouped(pathComponents)
                register(node.children, on: group)
            }
        }
    }

    private static func pageHandler(makePage: @escaping () -> any Page) -> (Request) async throws ->
        Response
    {
        { _ in
            Response(body: .init(string: makePage().renderHTML()))
        }
    }

    private static func vaporPathComponents(from path: [RoutePathComponent]) -> [PathComponent] {
        path.map { component in
            switch component {
            case .constant(let value):
                return .constant(value)
            case .parameter(let name):
                return .parameter(name)
            }
        }
    }
}
