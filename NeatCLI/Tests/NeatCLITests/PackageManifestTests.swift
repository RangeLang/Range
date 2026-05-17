import Foundation
@testable import NeatCLI
import Testing

@Suite("Package manifests")
struct PackageManifestTests {
    @Test("Package manifest includes remote metadata")
    func packageManifestIncludesRemoteMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-package-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)
        try """
            #package
            construct Project {
                let name: Title = Title("Fixture")
                let version: Version = Version(1.2.3)
                let author: String = "Test Author"
                let remote: String = "https://github.com/acme/fixture.git"
                let remotes: [Remote] = [
                    Remote(url: "https://github.com/acme/fixture.git"),
                    Remote(url: "git@github.com:acme/fixture.git"),
                ]
            }
            """.write(to: packageFile, atomically: true, encoding: .utf8)

        let manifest = try PackageManifestLoader.load(from: packageFile)

        #expect(manifest.name == "Fixture")
        #expect(manifest.version == "1.2.3")
        #expect(manifest.author == "Test Author")
        #expect(manifest.remote == "https://github.com/acme/fixture.git")
        #expect(manifest.remoteURLs == [
            "https://github.com/acme/fixture.git",
            "git@github.com:acme/fixture.git",
        ])
    }

    @Test("Package manifest requires typed package protocol fields")
    func packageManifestRequiresTypedPackageProtocolFields() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-package-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let packageFile = root.appendingPathComponent("Package.neat", isDirectory: false)
        try """
            #package
            construct Project {
                let name: Title = Title("Fixture")
                let version: Int = 1
                let author: String = "Test Author"
            }
            """.write(to: packageFile, atomically: true, encoding: .utf8)

        do {
            _ = try PackageManifestLoader.load(from: packageFile)
            Issue.record("Expected Package.neat validation to reject an untyped package version.")
        } catch {
            #expect(String(describing: error).contains("requires let version: Version"))
        }
    }
}
