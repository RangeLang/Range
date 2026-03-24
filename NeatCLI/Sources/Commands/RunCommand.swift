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
                let driver = SwiftBackendDriver()
                let buildRoot = try driver.emitProjectWorkspace(at: input ?? ".")
                try driver.runGeneratedWorkspace(at: buildRoot)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
