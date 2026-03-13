import ArgumentParser

extension NeatCLI {
    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update project modules and optionally the Neat CLI."
        )

        @Argument(help: "Project directory. Defaults to current directory.")
        var path: String?

        @Flag(
            name: .customLong("self"),
            help: "Also update the Neat CLI binary if run inside the NeatCLI repo."
        )
        var updateSelf: Bool = false

        mutating func run() throws {
            do {
                let updater = ProjectUpdater(path: path ?? ".", updateCLI: updateSelf)
                try updater.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
