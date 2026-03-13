

/// The main entry point for a Neat application.
/// A struct conforming to this protocol and marked with `@main`
/// will configure and run the server.
public protocol App {
    /// A parameterless initializer is required to start the app.
    init()

    /// Defines the application's sitemap and URL structure via the routing DSL.
    associatedtype AppRouter: RouteComponent = AnyRoute

    /// Declares global `<head>` content shared by every page.
    associatedtype AppHead: Head = AnyHead

    @RouteBuilder
    var router: AppRouter { get }

    @HeadBuilder
    var head: AppHead { get }
}

public extension App where AppHead == AnyHead {
    @HeadBuilder
    var head: AppHead {
        AnyHead(EmptyHead())
    }
}
