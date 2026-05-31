import ArgumentParser
import Foundation
import RangeSyntax

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
                let backend = BackendRegistry.default()
                let workspace = try backend.emitWorkspace(
                    project: project,
                    compiledProgram: compiledProgram
                )
                try backend.run(workspace: workspace)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
