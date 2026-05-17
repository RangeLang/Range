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
        #expect(source.contains(#"let version: String = "0.1.1""#))
    }

    @Test("Minor and major publish reset lower version components")
    func minorAndMajorPublishResetLowerVersionComponents() throws {
        let minorRoot = try temporaryProject(version: "1.2.3")
        let majorRoot = try temporaryProject(version: "1.2.3")

        #expect(try PackagePublisher(projectPath: minorRoot.path).publish(.minor).version == "1.3.0")
        #expect(try PackagePublisher(projectPath: majorRoot.path).publish(.major).version == "2.0.0")
    }

    private func temporaryProject(version: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-package-publish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            construct Fixture: Package {
                let version: String = "\(version)"
                let author: String = "Test Author"
            }
            """.write(to: root.appendingPathComponent("Package.neat"), atomically: true, encoding: .utf8)
        return root
    }
}
