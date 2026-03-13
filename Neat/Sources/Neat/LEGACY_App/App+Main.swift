public enum NeatBootstrap {
    public static func run<T: App>(_ appType: T.Type) async throws {
        let site = T()

        GlobalHeadRegistry.shared.register(head: AnyHead(site.head))

        let nodes = site.router.build()
        let router = RouterBuilder.build(from: nodes)
        RouterStore.set(router)
    }
}

public extension App {
    static func main() async throws {
        try await NeatBootstrap.run(Self.self)
    }
}
