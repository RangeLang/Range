import ArgumentParser

extension NeatCLI {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new .neat project."
        )

        @Argument(help: "Project name, or target path like ./MyApp.")
        var name: String?

        @Argument(help: "Target directory.")
        var path: String?

        mutating func run() throws {
            let resolvedName: String?
            let resolvedPath: String?

            if let providedPath = path {
                resolvedName = name
                resolvedPath = providedPath
            } else if let first = name, looksLikePath(first) {
                resolvedName = nil
                resolvedPath = first
            } else {
                resolvedName = name
                resolvedPath = nil
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
