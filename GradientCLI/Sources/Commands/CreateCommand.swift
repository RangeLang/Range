import ArgumentParser

extension NeatCLI {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new Neat project."
        )

        @Argument(help: "Project name.")
        var name: String?

        @Argument(help: "Target directory.")
        var path: String?

        mutating func run() throws {
            let resolvedName: String?
            let resolvedPath: String?

            if let name, path == nil, looksLikePath(name) {
                resolvedName = nil
                resolvedPath = name
            } else {
                resolvedName = name
                resolvedPath = path
            }

            do {
                let scaffolder = ProjectScaffolder(
                    initialName: resolvedName,
                    initialPath: resolvedPath
                )
                try scaffolder.run()
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func looksLikePath(_ value: String) -> Bool {
            value.hasPrefix("./")
                || value.hasPrefix("../")
                || value.hasPrefix("/")
                || value.hasPrefix("~/")
                || value.contains("/")
        }
    }
}
