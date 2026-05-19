import Foundation
@testable import GradientCLI
import Testing

@Suite("Package manifests")
struct PackageManifestTests {
    @Test("Package manifest includes remote metadata")
    func packageManifestIncludesRemoteMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradient-package-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let packageFile = root.appendingPathComponent("Package.gradient", isDirectory: false)
        try """
            #package
            construct Fixture {
                let name: Title("Fixture")
                let version: Version(1.2.3)
                let author: String("Test Author")
                let remote: String("https://github.com/acme/fixture.git")
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
            .appendingPathComponent("gradient-package-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let packageFile = root.appendingPathComponent("Package.gradient", isDirectory: false)
        try """
            #package
            construct Fixture {
                let name: Title("Fixture")
                let version: Int(1)
                let author: String("Test Author")
            }
            """.write(to: packageFile, atomically: true, encoding: .utf8)

        do {
            _ = try PackageManifestLoader.load(from: packageFile)
            Issue.record("Expected Package.gradient validation to reject an untyped package version.")
        } catch {
            #expect(String(describing: error).contains("requires let version: Version"))
        }
    }

    @Test("Package manifest resolves git remotes")
    func packageManifestResolvesGitRemotes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradient-package-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try run("git", "init", in: root)
        try run("git", "remote", "add", "origin", "https://github.com/acme/fixture.git", in: root)

        let packageFile = root.appendingPathComponent("Package.gradient", isDirectory: false)
        try """
            #package
            construct Fixture {
                let name: Title("Fixture")
                let version: Version(1.2.3)
                let author: String("Test Author")
            }
            """.write(to: packageFile, atomically: true, encoding: .utf8)

        let manifest = try PackageManifestLoader.load(from: packageFile)

        #expect(manifest.name == "Fixture")
        #expect(manifest.remoteURLs == ["https://github.com/acme/fixture.git"])
    }

    @discardableResult
    private func run(_ command: String, _ arguments: String..., in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PackageManifestTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
            )
        }
        return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
