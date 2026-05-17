import Foundation
@testable import NeatCLI
import Testing

@Suite("Package subscription")
struct PackageSubscriptionManagerTests {
    @Test("Installed packages are searchable by reference and manifest name")
    func installedPackagesAreSearchable() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".neat/Packages/acme/logger/Package.neat"),
            name: "LoggingTools"
        )
        try writePackage(
            at: root.appendingPathComponent(".neat/Packages/acme/ui/Package.neat"),
            name: "InterfaceKit"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)
        let packages = try manager.installedPackages(in: root)

        #expect(packages.map(\.reference) == ["acme/logger", "acme/ui"])
        #expect(manager.matchingPackages(packages, search: "logging").map(\.reference) == ["acme/logger"])
        #expect(manager.matchingPackages(packages, search: "acme ui").map(\.reference) == ["acme/ui"])
    }

    @Test("Subscribe adds the selected installed module to Package.neat")
    func subscribeAddsSelectedInstalledModule() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".neat/Packages/acme/logger/Package.neat"),
            name: "LoggingTools"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)
        let action = try manager.subscribe(search: "logger")

        let source = try String(
            contentsOf: root.appendingPathComponent("Package.neat"),
            encoding: .utf8
        )
        #expect(action == .subscribed)
        #expect(source.contains(#"Module("acme/logger")"#))
    }

    @Test("Subscribe browses when search is empty or ambiguous")
    func subscribeBrowsesWhenSearchIsEmptyOrAmbiguous() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".neat/Packages/acme/logger/Package.neat"),
            name: "LoggingTools"
        )
        try writePackage(
            at: root.appendingPathComponent(".neat/Packages/acme/log-viewer/Package.neat"),
            name: "LogViewer"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)

        #expect(try manager.subscribe(search: "") == .browse)
        #expect(try manager.subscribe(search: "log") == .browse)
    }

    private func temporaryProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-package-subscribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writePackage(at: root.appendingPathComponent("Package.neat"), name: "Fixture")
        return root
    }

    private func writePackage(at url: URL, name: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
            construct \(name): Package {

            }
            """.write(to: url, atomically: true, encoding: .utf8)
    }
}
