import Foundation
@testable import RangeCLI
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

        #expect(link.path == fixture.root.appendingPathComponent(".range/current/\(RangeVersion.current)/range").path)
        let versionedBinary = fixture.root
            .appendingPathComponent(".range/releases/\(RangeVersion.current)/range")
        let current = fixture.root.appendingPathComponent(".range/current/\(RangeVersion.current)")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: current.path) == versionedBinary.deletingLastPathComponent().path)
        #expect(try String(contentsOf: versionedBinary, encoding: .utf8) == "#!/usr/bin/env bash\nexit 0\n")

        let receipt = fixture.root.appendingPathComponent(".range/Links/range.package-link.json")
        let receiptSource = try String(contentsOf: receipt, encoding: .utf8)
        #expect(receiptSource.contains(#""kind" : "range.package-link""#))
        #expect(receiptSource.contains(#""selectedVersion" : "\#(RangeVersion.current)""#))
        #expect(receiptSource.contains(#""source" : "\#(fixture.binary.path)""#))
        #expect(receiptSource.contains(#""versionedBinary" : "\#(versionedBinary.path)""#))
    }

    @Test("Package file path resolves to package root")
    func packageFilePathResolvesToPackageRoot() throws {
        let fixture = try temporaryPackage()
        let link = try ProjectBinaryLinker(
            projectPath: fixture.root.appendingPathComponent("Package.range").path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(link.path == fixture.root.appendingPathComponent(".range/current/\(RangeVersion.current)/range").path)
    }

    @Test("Existing symlink upgrades to versioned package install")
    func existingSymlinkUpgradesToVersionedPackageInstall() throws {
        let fixture = try temporaryPackage()
        let link = fixture.root.appendingPathComponent(".range/current", isDirectory: false)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.binary)

        let packaged = try ProjectBinaryLinker(
            projectPath: fixture.root.path,
            binaryPath: fixture.binary.path
        ).run()

        #expect(packaged.path == fixture.root.appendingPathComponent(".range/current/\(RangeVersion.current)/range").path)
        let versionedBinary = fixture.root
            .appendingPathComponent(".range/releases/\(RangeVersion.current)/range")
        let currentVersion = fixture.root.appendingPathComponent(".range/current/\(RangeVersion.current)")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: currentVersion.path) == versionedBinary.deletingLastPathComponent().path)
        #expect(try String(contentsOf: versionedBinary, encoding: .utf8) == "#!/usr/bin/env bash\nexit 0\n")
    }

    private func temporaryPackage() throws -> (root: URL, binary: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-binary-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            @package
            construct Project {
                let name: Title("Linked")
                let version: Version(0.1.0)
                let author: "Test Author"
            }
            """.write(to: root.appendingPathComponent("Package.range"), atomically: true, encoding: .utf8)

        let binary = root.appendingPathComponent("installed-range", isDirectory: false)
        try "#!/usr/bin/env bash\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binary.path
        )
        return (root, binary)
    }
}
