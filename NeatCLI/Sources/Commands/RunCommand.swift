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
                let runner = MainProgramRunner(path: input ?? ".")
                try runner.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
