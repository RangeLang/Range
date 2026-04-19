import ArgumentParser
import Foundation
import NeatSyntax

extension NeatCLI {
    struct Graph: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build and print the application graph for a Neat file or project."
        )

        @Argument(help: "Project directory or source .neat file to inspect.")
        var input: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(at: input ?? ".")
                let program = try ProjectSourceValidator.programModel(for: project)
                print(program.applicationGraph.render())
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
