import ArgumentParser

extension NeatCLI {
    struct LSP: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the Neat language server over stdio."
        )

        mutating func run() throws {
            do {
                var server = NeatLanguageServer()
                try server.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
