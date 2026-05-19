import Foundation
@testable import GradientCLI
import Testing

@Suite("Project binary linking")
struct ProjectBinaryLinkerTests {
    @Test("Install versioned binary into package root")
    func installVersionedBinaryIntoPackageRoot() throws {
        let fixture = try temporaryPackage()
        let link = try ProjectBinaryLinker(
            projectPath: fixture.root.path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(link.path == fixture.root.appendingPathComponent(".gradient/bin/gradient").path)
        let versionedBinary = fixture.root
            .appendingPathComponent(".gradient/GradientCLI/\(GradientVersion.current)/bin/gradient")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == versionedBinary.path)
        #expect(try String(contentsOf: versionedBinary, encoding: .utf8) == "#!/usr/bin/env bash\nexit 0\n")

        let receipt = fixture.root.appendingPathComponent(".gradient/Links/gradient.package-link.json")
        let receiptSource = try String(contentsOf: receipt, encoding: .utf8)
        #expect(receiptSource.contains(#""kind" : "gradient.package-link""#))
        #expect(receiptSource.contains(#""selectedVersion" : "\#(GradientVersion.current)""#))
        #expect(receiptSource.contains(#""source" : "\#(fixture.binary.path)""#))
        #expect(receiptSource.contains(#""versionedBinary" : "\#(versionedBinary.path)""#))
    }

    @Test("Package file path resolves to package root")
    func packageFilePathResolvesToPackageRoot() throws {
        let fixture = try temporaryPackage()
        let link = try ProjectBinaryLinker(
            projectPath: fixture.root.appendingPathComponent("Package.gradient").path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(link.path == fixture.root.appendingPathComponent(".gradient/bin/gradient").path)
    }

    @Test("Existing symlink upgrades to versioned package install")
    func existingSymlinkUpgradesToVersionedPackageInstall() throws {
        let fixture = try temporaryPackage()
        let link = fixture.root.appendingPathComponent(".gradient/bin/gradient", isDirectory: false)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.binary)

        let packaged = try ProjectBinaryLinker(
            projectPath: fixture.root.path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(packaged.path == link.path)
        let versionedBinary = fixture.root
            .appendingPathComponent(".gradient/GradientCLI/\(GradientVersion.current)/bin/gradient")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: packaged.path) == versionedBinary.path)
        #expect(try String(contentsOf: versionedBinary, encoding: .utf8) == "#!/usr/bin/env bash\nexit 0\n")
    }

    private func temporaryPackage() throws -> (root: URL, binary: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradient-binary-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            #package
            construct Project {
                let name: Title("Linked")
                let version: Version(0.1.0)
                let author: String("Test Author")
            }
            """.write(to: root.appendingPathComponent("Package.gradient"), atomically: true, encoding: .utf8)

        let binary = root.appendingPathComponent("installed-gradient", isDirectory: false)
        try "#!/usr/bin/env bash\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binary.path
        )
        return (root, binary)
    }
}
