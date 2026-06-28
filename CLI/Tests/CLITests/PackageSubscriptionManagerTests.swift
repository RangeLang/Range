import Foundation
@testable import CLI
import Testing

@Suite("Package subscription")
struct PackageSubscriptionManagerTests {
    @Test("Installed packages are searchable by reference and manifest name")
    func installedPackagesAreSearchable() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".range/Packages/acme/logger/Project.range"),
            name: "LoggingTools"
        )
        try writePackage(
            at: root.appendingPathComponent(".range/Packages/acme/ui/Project.range"),
            name: "InterfaceKit"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)
        let packages = try manager.installedPackages(in: root)

        #expect(packages.map(\.reference) == ["acme/logger", "acme/ui"])
        #expect(packages.map(\.version) == ["0.1.0", "0.1.0"])
        #expect(manager.matchingPackages(packages, search: "logging").map(\.reference) == ["acme/logger"])
        #expect(manager.matchingPackages(packages, search: "acme ui").map(\.reference) == ["acme/ui"])
    }

    @Test("Subscribe adds the selected installed module to Project.range")
    func subscribeAddsSelectedInstalledModule() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".range/Packages/acme/logger/Project.range"),
            name: "LoggingTools"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)
        let action = try manager.subscribe(search: "logger")

        let source = try String(
            contentsOf: root.appendingPathComponent("Project.range"),
            encoding: .utf8
        )
        #expect(action == .subscribed)
        #expect(source.contains(#"@let(name: "modules")"#))
        #expect(source.contains(#"String(\"acme/logger\")"#))
        _ = try PackageManifestLoader.load(from: root.appendingPathComponent("Project.range"))
    }

    @Test("Subscribe browses when search is empty or ambiguous")
    func subscribeBrowsesWhenSearchIsEmptyOrAmbiguous() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".range/Packages/acme/logger/Project.range"),
            name: "LoggingTools"
        )
        try writePackage(
            at: root.appendingPathComponent(".range/Packages/acme/log-viewer/Project.range"),
            name: "LogViewer"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)

        #expect(try manager.subscribe(search: "") == .browse)
        #expect(try manager.subscribe(search: "log") == .browse)
    }

    private func temporaryProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-package-subscribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writePackage(at: root.appendingPathComponent("Project.range"), name: "Fixture")
        return root
    }

    private func writePackage(at url: URL, name: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
            @construct(name: "Project") {
                @let(name: "name") {
                    @value(type: "Title", current: "Title(\\\"\(name)\\\")")
                }
                @let(name: "version") {
                    @value(type: "Version", current: "Version(0.1.0)")
                }
                @let(name: "author") {
                    @value(type: "String", current: "String(\\\"Test Author\\\")")
                }
            }
            """.write(to: url, atomically: true, encoding: .utf8)
    }
}
