import ArgumentParser

extension NeatCLI {
    struct Package: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage installed Neat packages.",
            subcommands: [
                Subscribe.self
            ]
        )

        struct Subscribe: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Subscribe this project to an already installed package."
            )

            @Argument(
                parsing: .remaining,
                help: "Search terms for packages under .neat/Packages."
            )
            var terms: [String] = []

            @Option(
                name: .shortAndLong,
                help: "Project directory. Defaults to current directory."
            )
            var path: String = "."

            @Option(
                name: .customLong("cloud-limit"),
                help: "Maximum number of cloud packages to show while browsing."
            )
            var cloudLimit: Int = 5

            mutating func run() throws {
                do {
                    let manager = PackageSubscriptionManager(projectPath: path)
                    let query = terms.joined(separator: " ")
                    let action = try manager.subscribe(search: query)

                    if action.shouldDisplayDiscovery {
                        let cloudResults =
                            cloudLimit > 0
                            ? (try? PackageSearcher().search(
                                query: query.isEmpty ? "neat" : query,
                                limit: cloudLimit
                            )) ?? []
                            : []
                        manager.displayDiscovery(search: query, cloudResults: cloudResults)
                    }
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }
    }
}
