import ArgumentParser
import NeatSyntax

extension NeatCLI {
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a .neat project."
        )

        @Argument(help: "Project directory.")
        var path: String = "."

        @Option(name: .shortAndLong, help: "HTTP port for the runtime server.")
        var port: Int = 4173

        mutating func run() throws {
            do {
                let runner = ProjectRunner(path: path, port: port)
                try runner.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
