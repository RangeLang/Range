import Foundation
@testable import NeatCLI
import Testing

@Suite("Package publishing")
struct PackagePublisherTests {
    @Test("Patch publish bumps package version")
    func patchPublishBumpsPackageVersion() throws {
        let root = try temporaryProject(version: "0.1.0")
        let published = try PackagePublisher(projectPath: root.path).publish(.patch)
        let source = try String(contentsOf: root.appendingPathComponent("Package.neat"), encoding: .utf8)

        #expect(published.name == "Fixture")
        #expect(published.version == "0.1.1")
        #expect(published.git == .skipped("not a git repository"))
        #expect(source.contains(#"let version: String = "0.1.1""#))
    }

    @Test("Minor and major publish reset lower version components")
    func minorAndMajorPublishResetLowerVersionComponents() throws {
        let minorRoot = try temporaryProject(version: "1.2.3")
        let majorRoot = try temporaryProject(version: "1.2.3")

        #expect(try PackagePublisher(projectPath: minorRoot.path).publish(.minor).version == "1.3.0")
        #expect(try PackagePublisher(projectPath: majorRoot.path).publish(.major).version == "2.0.0")
    }

    @Test("Publish commits and tags package version in git repositories")
    func publishCommitsAndTagsPackageVersionInGitRepositories() throws {
        let root = try temporaryProject(version: "0.1.0")
        try run("git", "init", in: root)
        try run("git", "config", "user.email", "test@example.com", in: root)
        try run("git", "config", "user.name", "Test User", in: root)
        try run("git", "add", "Package.neat", in: root)
        try run("git", "commit", "-m", "Initial package", in: root)

        let published = try PackagePublisher(projectPath: root.path).publish(.patch, push: false)
        let tags = try run("git", "tag", in: root)

        guard case .published(_, let tag, let pushed) = published.git else {
            Issue.record("Expected git publish result.")
            return
        }
        #expect(tag == "v0.1.1")
        #expect(!pushed)
        #expect(tags.split(separator: "\n").contains("v0.1.1"))
    }

    private func temporaryProject(version: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-package-publish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            construct Fixture: Package {
                let version: String = "\(version)"
                let author: String = "Test Author"
                let remotes: [Remote] = []
            }
            """.write(to: root.appendingPathComponent("Package.neat"), atomically: true, encoding: .utf8)
        return root
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
                domain: "PackagePublisherTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
            )
        }
        return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
