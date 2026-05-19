import ArgumentParser
import GradientSyntax

extension GradientCLI {
    struct LSP: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the Gradient language server over stdio."
        )

        mutating func run() throws {
            do {
                var server = GradientLanguageServer()
                try server.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
