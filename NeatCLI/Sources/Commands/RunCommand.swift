import ArgumentParser
import Foundation
import NeatSyntax

extension NeatCLI {
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a Neat main program."
        )

        @Argument(help: "Project directory or source .neat file to run.")
        var input: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(requireManifestForDirectory: true)
                )
                let semanticProgram = try ProjectSourceValidator.validatedSemanticProgram(
                    for: project
                )
                let backend = BackendRegistry.default()
                let workspace = try backend.emitWorkspace(
                    project: project,
                    semanticProgram: semanticProgram
                )
                try backend.run(workspace: workspace)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
