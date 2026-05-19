import Foundation
@testable import NeatCLI
import Testing

@Suite("Project scaffolding")
struct ProjectScaffolderTests {
    @Test("Create links project workspace to machine project store")
    func createLinksProjectWorkspaceToMachineProjectStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-project-scaffold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try ProjectScaffolder(initialName: "Linked Packages", initialPath: root.path).run()

        let projectWorkspace = root.appendingPathComponent(".neat", isDirectory: true)
        let workspaceDestination = try FileManager.default.destinationOfSymbolicLink(
            atPath: projectWorkspace.path
        )
        #expect(workspaceDestination.contains("/.neat/Projects/linked-packages-"))

        let projectPackages = root
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: projectPackages.path)
        let machinePackages = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".neat", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
            .standardizedFileURL

        #expect(destination == machinePackages.path)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".neat/Build").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".neat/Artifacts").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".neat/.scripts").path))
        _ = try PackageSubscriptionManager(projectPath: root.path).installedPackages(in: root)
    }
}
