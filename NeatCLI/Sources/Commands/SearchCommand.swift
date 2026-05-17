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

        mutating func run() throws {
            do {
                let searcher = PackageSearcher()
                if terms.isEmpty {
                    try runInteractiveSearch(searcher: searcher)
                } else {
                    let results = try searcher.search(query: terms.joined(separator: " "), limit: limit)
                    render(results)
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
                render(results)
            }
        }

        private func render(_ results: [PackageSearchResult]) {
            guard !results.isEmpty else {
                TerminalLog.out("No packages found. Try another search.", level: .waiting)
                return
            }

            TerminalLog.out("Found \(results.count) package\(results.count == 1 ? "" : "s").", level: .success)

            for result in results {
                let stars = result.stars == 1 ? "1 star" : "\(result.stars) stars"
                print("")
                print(TerminalLog.style(result.package, level: .change, bold: true) + "  " + TerminalLog.subtleStdout(stars))

                if let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !description.isEmpty
                {
                    print(description)
                }

                print(TerminalLog.subtleStdout(result.url.absoluteString))
                print(TerminalLog.subtleStdout(result.manifestURL.absoluteString))
                print(TerminalLog.subtleStdout("Package.neat: Module(\"\(result.package)\")"))
            }
        }
    }
}
