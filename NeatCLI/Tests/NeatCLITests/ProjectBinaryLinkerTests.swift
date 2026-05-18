import Foundation
@testable import NeatCLI
import Testing

@Suite("Project binary linking")
struct ProjectBinaryLinkerTests {
    @Test("Link installed binary into package root")
    func linkInstalledBinaryIntoPackageRoot() throws {
        let fixture = try temporaryPackage()
        let link = try ProjectBinaryLinker(
            projectPath: fixture.root.path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(link.path == fixture.root.appendingPathComponent(".neat/bin/neat").path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == fixture.binary.path)
    }

    @Test("Package file path resolves to package root")
    func packageFilePathResolvesToPackageRoot() throws {
        let fixture = try temporaryPackage()
        let link = try ProjectBinaryLinker(
            projectPath: fixture.root.appendingPathComponent("Package.neat").path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(link.path == fixture.root.appendingPathComponent(".neat/bin/neat").path)
    }

    private func temporaryPackage() throws -> (root: URL, binary: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-binary-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            @package {
                let name: Title("Linked")
                let version: Version(0.1.0)
            }
            """.write(to: root.appendingPathComponent("Package.neat"), atomically: true, encoding: .utf8)

        let binary = root.appendingPathComponent("installed-neat", isDirectory: false)
        try "#!/usr/bin/env bash\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binary.path
        )
        return (root, binary)
    }
}
