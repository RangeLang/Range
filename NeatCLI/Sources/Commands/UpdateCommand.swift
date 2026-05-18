import ArgumentParser
import NeatSyntax

extension NeatCLI {
    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update the Neat CLI or project modules."
        )

        @Argument(help: "Project directory. When omitted, updates the Neat CLI.")
        var path: String?

        @Flag(
            name: .customLong("self"),
            help: "Also update the Neat CLI after updating project modules."
        )
        var updateSelf: Bool = false

        mutating func run() throws {
            do {
                if let path {
                    let updater = ProjectUpdater(path: path, updateCLI: updateSelf)
                    try updater.run()
                } else {
                    try ProjectUpdater.updateInstalledCLI()
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
