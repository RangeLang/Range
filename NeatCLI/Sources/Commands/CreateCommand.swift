import ArgumentParser

extension NeatCLI {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new Neat project."
        )

        @Argument(help: "Project kind (`web`, `program`) or project name.")
        var first: String?

        @Argument(help: "Project name or target directory.")
        var second: String?

        @Argument(help: "Target directory.")
        var third: String?

        mutating func run() throws {
            let resolvedKind: ProjectScaffolder.ProjectKind?
            let resolvedName: String?
            let resolvedPath: String?

            if let first, let kind = ProjectScaffolder.ProjectKind(rawValue: first.lowercased()) {
                resolvedKind = kind
                if let providedPath = third {
                    resolvedName = second
                    resolvedPath = providedPath
                } else if let second, looksLikePath(second) {
                    resolvedName = nil
                    resolvedPath = second
                } else {
                    resolvedName = second
                    resolvedPath = nil
                }
            } else {
                resolvedKind = nil
                if let providedPath = second {
                    resolvedName = first
                    resolvedPath = providedPath
                } else if let first, looksLikePath(first) {
                    resolvedName = nil
                    resolvedPath = first
                } else {
                    resolvedName = first
                    resolvedPath = nil
                }
            }

            do {
                let scaffolder = ProjectScaffolder(
                    initialKind: resolvedKind,
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
