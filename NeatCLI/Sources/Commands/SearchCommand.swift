import ArgumentParser
import Foundation

extension NeatCLI {
    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search the network for Neat packages."
        )

        @Argument(
            parsing: .remaining,
            help: "Optional search terms."
        )
        var terms: [String] = []

        @Option(
            name: .shortAndLong,
            help: "Maximum number of packages to show."
        )
        var limit: Int = 10

        @Option(
            name: .shortAndLong,
            help: "Project directory for local installed packages. Defaults to current directory."
        )
        var path: String = "."

        mutating func run() throws {
            do {
                let searcher = PackageSearcher()
                if terms.isEmpty {
                    try runInteractiveSearch(searcher: searcher)
                } else {
                    let query = terms.joined(separator: " ")
                    let results = try searcher.search(query: query, limit: limit)
                    render(query: query, cloudResults: results)
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func runInteractiveSearch(searcher: PackageSearcher) throws {
            TerminalLog.out("Package Search", level: .change, bold: true)
            print(TerminalLog.subtleStdout("Type a search term. Press Enter on an empty line to exit."))

            while true {
                print("")
                fputs("Search: ", stdout)
                fflush(stdout)

                guard let rawQuery = readLine() else {
                    return
                }

                let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty || query == "q" || query == "quit" {
                    return
                }

                let results = try searcher.search(query: query, limit: limit)
                render(query: query, cloudResults: results)
            }
        }

        private func render(query: String, cloudResults: [PackageSearchResult]) {
            let projectRoot = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            let manager = PackageSubscriptionManager(projectPath: path)
            let installed = (try? manager.installedPackages(in: projectRoot)) ?? []
            let installedMatches = manager.matchingPackages(installed, search: query)

            print(TerminalLog.style("Local", level: .change, bold: true))
            print(TerminalLog.subtleStdout("\(installedMatches.count) of \(installed.count) installed"))
            if installedMatches.isEmpty {
                print(TerminalLog.subtleStdout("No installed packages match '\(query)'."))
            } else {
                for package in installedMatches {
                    print("  " + TerminalLog.style(package.reference, level: .change, bold: true) + "  " + TerminalLog.subtleStdout(package.name))
                }
            }

            print("")
            print(TerminalLog.style("Cloud", level: .optimization, bold: true))
            guard !cloudResults.isEmpty else {
                print(TerminalLog.subtleStdout("No cloud packages found. Try another search."))
                return
            }

            print(TerminalLog.subtleStdout("\(cloudResults.count) found"))
            for result in cloudResults {
                let stars = result.stars == 1 ? "1 star" : "\(result.stars) stars"
                print("  " + TerminalLog.style(result.package, level: .optimization, bold: true) + "  " + TerminalLog.subtleStdout(stars))

                if let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !description.isEmpty
                {
                    print("    " + description)
                }

                print("    " + TerminalLog.subtleStdout(result.url.absoluteString))
                print("    " + TerminalLog.subtleStdout("Package.neat: Module(\"\(result.package)\")"))
            }
        }
    }
}
