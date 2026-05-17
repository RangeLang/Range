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
                let query = terms.isEmpty ? "neat" : terms.joined(separator: " ")
                let results = try PackageSearcher().search(query: query, limit: limit)
                render(results)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func render(_ results: [PackageSearchResult]) {
            guard !results.isEmpty else {
                TerminalLog.out("No packages found.", level: .waiting)
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
