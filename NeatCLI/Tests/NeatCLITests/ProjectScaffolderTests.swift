import Foundation
@testable import NeatCLI
import Testing

@Suite("Project scaffolding")
struct ProjectScaffolderTests {
    @Test("Create links project packages to machine package store")
    func createLinksProjectPackagesToMachinePackageStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-project-scaffold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try ProjectScaffolder(initialName: "Linked Packages", initialPath: root.path).run()

        let projectPackages = root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: projectPackages.path)
        let machinePackages = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
            .standardizedFileURL

        #expect(destination == machinePackages.path)
    }
}
