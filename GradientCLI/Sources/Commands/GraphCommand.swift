import ArgumentParser
import Foundation
import GradientSyntax

extension GradientCLI {
    struct Graph: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build and print the application graph for a Gradient file or project."
        )

        @Argument(help: "Project directory or source .gradient file to inspect.")
        var input: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(at: input ?? ".")
                let compiledProgram = try ProjectSourceValidator.compiledProgram(for: project)
                print(compiledProgram.applicationGraph.render())
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
