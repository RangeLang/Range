import ArgumentParser
import RangeSyntax

extension RangeCLI {
    struct LSP: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the Range language server over stdio."
        )

        mutating func run() throws {
            do {
                var server = RangeLanguageServer()
                try server.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
