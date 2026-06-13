import ArgumentParser
import Foundation
import RangeEmission
import RangeCompiler

extension CLI {
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a Range main program."
        )

        @Argument(help: "Project directory or source .range file to run.")
        var input: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(requireManifestForDirectory: true)
                )
                let compiledProgram = try ProjectSourceValidator.validatedCompiledProgram(
                    for: project
                )
                let backend = SwiftBackend()
                let workspaceRoot = try backend.emitWorkspace(
                    project: SwiftBackendProject(
                        projectFiles: project.projectFiles,
                        isSingleFile: project.isSingleFile,
                        buildRoot: project.defaultBuildRoot
                    ),
                    compiledProgram: compiledProgram
                )
                try backend.run(workspaceRoot: workspaceRoot)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
