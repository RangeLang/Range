import ArgumentParser
import NeatSyntax

extension NeatCLI {
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reserved for target runtimes."
        )

        mutating func run() throws {
            ErrorPresenter.printError(
                ValidationError("`neat run` is unavailable until a target backend is linked.")
            )
            throw ExitCode.failure
        }
    }
}
