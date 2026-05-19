import Foundation
@testable import RangeCLI
import Testing

@Suite("Project scripts")
struct ProjectScriptStoreTests {
    @Test("Create stores starter script under dot scripts")
    func createStoresStarterScriptUnderDotScripts() throws {
        let root = try temporaryPackage()
        let script = try ProjectScriptStore(projectPath: root.path).create("build")

        #expect(script.path == root.appendingPathComponent(".range/.scripts/build.range").path)
        let source = try String(contentsOf: script, encoding: .utf8)
        #expect(source.contains(#"Logger.info("Running build")"#))
    }

    @Test("Save normalizes script extension and content")
    func saveNormalizesScriptExtensionAndContent() throws {
        let root = try temporaryPackage()
        let script = try ProjectScriptStore(projectPath: root.path).save(
            "deploy.range",
            content: "#main {}"
        )

        #expect(script.lastPathComponent == "deploy.range")
        #expect(try String(contentsOf: script, encoding: .utf8) == "#main {}\n")
    }

    @Test("List returns saved scripts")
    func listReturnsSavedScripts() throws {
        let root = try temporaryPackage()
        let store = ProjectScriptStore(projectPath: root.path)
        _ = try store.save("deploy", content: "#main {}")
        _ = try store.save("build", content: "#main {}")

        #expect(try store.list().map(\.lastPathComponent) == ["build.range", "deploy.range"])
    }

    @Test("Rejects path script names")
    func rejectsPathScriptNames() throws {
        let root = try temporaryPackage()

        do {
            _ = try ProjectScriptStore(projectPath: root.path).create("../escape")
            Issue.record("Expected path script name to fail.")
        } catch {
            #expect(String(describing: error).contains("Script name must be a file name"))
        }
    }

    private func temporaryPackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-script-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            #package
            construct Project {
                let name: Title("Scripts")
                let version: Version(0.1.0)
                let author: String("Test Author")
            }
            """.write(to: root.appendingPathComponent("Package.range"), atomically: true, encoding: .utf8)
        return root
    }
}
