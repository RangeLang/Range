public enum RoutePathComponent: Hashable {
    case constant(String)
    case parameter(String)

    public var description: String {
        switch self {
        case .constant(let value):
            return value
        case .parameter(let name):
            return ":\(name)"
        }
    }
}

public struct RouteNode {
    public let path: [RoutePathComponent]
    public let pageType: (any Page.Type)?
    public let makePage: (() -> any Page)?
    public let children: [RouteNode]

    public init(
        path: [RoutePathComponent],
        pageType: (any Page.Type)?,
        makePage: (() -> any Page)?,
        children: [RouteNode]
    ) {
        self.path = path
        self.pageType = pageType
        self.makePage = makePage
        self.children = children
    }
}

extension String {
    var routePathComponents: [RoutePathComponent] {
        self.split(separator: "/").map { segment in
            if segment.hasPrefix(":") {
                return .parameter(String(segment.dropFirst()))
            }
            return .constant(String(segment))
        }
    }
}
