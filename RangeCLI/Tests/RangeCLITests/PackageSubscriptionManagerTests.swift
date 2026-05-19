import Foundation
@testable import GradientCLI
import Testing

@Suite("Package subscription")
struct PackageSubscriptionManagerTests {
    @Test("Installed packages are searchable by reference and manifest name")
    func installedPackagesAreSearchable() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".gradient/Packages/acme/logger/Package.gradient"),
            name: "LoggingTools"
        )
        try writePackage(
            at: root.appendingPathComponent(".gradient/Packages/acme/ui/Package.gradient"),
            name: "InterfaceKit"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)
        let packages = try manager.installedPackages(in: root)

        #expect(packages.map(\.reference) == ["acme/logger", "acme/ui"])
        #expect(packages.map(\.version) == ["0.1.0", "0.1.0"])
        #expect(manager.matchingPackages(packages, search: "logging").map(\.reference) == ["acme/logger"])
        #expect(manager.matchingPackages(packages, search: "acme ui").map(\.reference) == ["acme/ui"])
    }

    @Test("Subscribe adds the selected installed module to Package.gradient")
    func subscribeAddsSelectedInstalledModule() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".gradient/Packages/acme/logger/Package.gradient"),
            name: "LoggingTools"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)
        let action = try manager.subscribe(search: "logger")

        let source = try String(
            contentsOf: root.appendingPathComponent("Package.gradient"),
            encoding: .utf8
        )
        #expect(action == .subscribed)
        #expect(source.contains(#"let modules: [String] = ["acme/logger"]"#))
        _ = try PackageManifestLoader.load(from: root.appendingPathComponent("Package.gradient"))
    }

    @Test("Subscribe browses when search is empty or ambiguous")
    func subscribeBrowsesWhenSearchIsEmptyOrAmbiguous() throws {
        let root = try temporaryProject()
        try writePackage(
            at: root.appendingPathComponent(".gradient/Packages/acme/logger/Package.gradient"),
            name: "LoggingTools"
        )
        try writePackage(
            at: root.appendingPathComponent(".gradient/Packages/acme/log-viewer/Package.gradient"),
            name: "LogViewer"
        )

        let manager = PackageSubscriptionManager(projectPath: root.path)

        #expect(try manager.subscribe(search: "") == .browse)
        #expect(try manager.subscribe(search: "log") == .browse)
    }

    private func temporaryProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradient-package-subscribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writePackage(at: root.appendingPathComponent("Package.gradient"), name: "Fixture")
        return root
    }

    private func writePackage(at url: URL, name: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
            #package
            construct Project {
                let name: Title("\(name)")
                let version: Version(0.1.0)
                let author: String("Test Author")
            }
            """.write(to: url, atomically: true, encoding: .utf8)
    }
}
