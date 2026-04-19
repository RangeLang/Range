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
                let programModel = try ProjectSourceValidator.validatedProgramModel(
                    for: project
                )
                let backend = BackendRegistry.default()
                let workspace = try backend.emitWorkspace(
                    project: project,
                    programModel: programModel
                )
                try backend.run(workspace: workspace)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
