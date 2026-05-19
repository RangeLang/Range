import Foundation
@testable import GradientCLI
import Testing

@Suite("Project scaffolding")
struct ProjectScaffolderTests {
    @Test("Create links project workspace to machine project store")
    func createLinksProjectWorkspaceToMachineProjectStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gradient-project-scaffold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try ProjectScaffolder(initialName: "Linked Packages", initialPath: root.path).run()

        let projectWorkspace = root.appendingPathComponent(".gradient", isDirectory: true)
        let workspaceDestination = try FileManager.default.destinationOfSymbolicLink(
            atPath: projectWorkspace.path
        )
        #expect(workspaceDestination.contains("/.gradient/Projects/linked-packages-"))

        let projectPackages = root
            .appendingPathComponent(".gradient", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: projectPackages.path)
        let machinePackages = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gradient", isDirectory: true)
            .appendingPathComponent("Packages", isDirectory: true)
            .standardizedFileURL

        #expect(destination == machinePackages.path)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".gradient/Build").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".gradient/Artifacts").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".gradient/.scripts").path))
        _ = try PackageSubscriptionManager(projectPath: root.path).installedPackages(in: root)
    }
}
