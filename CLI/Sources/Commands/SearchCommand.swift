import ArgumentParser
import Foundation

extension CLI.Package {
    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search the network for Range packages."
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
                    try renderSearch(query: query, searcher: searcher)
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

                try renderSearch(query: query, searcher: searcher)
            }
        }

        private func renderSearch(query: String, searcher: PackageSearcher) throws {
            renderInstalledSection(
                title: "Machine",
                countLabel: "downloaded",
                root: machinePackageRoot(),
                query: query
            )
            print("")
            renderInstalledSection(
                title: "Project",
                countLabel: "installed",
                root: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL,
                query: query
            )
            print("")
            renderCloudLoading()
            let results = try runCloudSearchWithSpinner(query: query, searcher: searcher)
            renderCloud(results)
        }

        private func renderInstalledSection(
            title: String,
            countLabel: String,
            root: URL,
            query: String
        ) {
            let manager = PackageSubscriptionManager(projectPath: path)
            let installed = (try? manager.installedPackages(in: root)) ?? []
            let installedMatches = manager.matchingPackages(installed, search: query)

            print(TerminalLog.style(title, level: .change, bold: true))
            print(TerminalLog.captionStdout("\(installed.count) \(countLabel)"))
            if installedMatches.isEmpty {
                print(TerminalLog.subtleStdout("No \(title.lowercased()) packages match '\(query)'."))
            } else {
                for package in installedMatches {
                    print("  " + packageRow(
                        reference: package.reference,
                        version: package.version ?? "unknown",
                        level: .change
                    ))
                }
            }
        }

        private func machinePackageRoot() -> URL {
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        }

        private func renderCloudLoading(frame: String? = nil) {
            print(TerminalLog.style("Cloud", level: .optimization, bold: true))
            let suffix = frame.map { " \($0)" } ?? ""
            print(TerminalLog.subtleStdout("Loading cloud packages\(suffix)..."))
        }

        private func renderCloud(_ cloudResults: [PackageSearchResult]) {
            replaceCloudLines()

            print(TerminalLog.style("Cloud", level: .optimization, bold: true))
            guard !cloudResults.isEmpty else {
                print(TerminalLog.subtleStdout("No cloud packages found. Try another search."))
                return
            }

            print(TerminalLog.subtleStdout("\(cloudResults.count) found"))
            for result in cloudResults {
                let stars = result.stars == 1 ? "1 star" : "\(result.stars) stars"
                print("  " + packageRow(
                    reference: result.package,
                    version: "unknown",
                    level: .optimization
                ) + "  " + TerminalLog.subtleStdout(stars))

                if let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !description.isEmpty
                {
                    print("    " + description)
                }

                print("    " + TerminalLog.subtleStdout(result.url.absoluteString))
                print("    " + TerminalLog.subtleStdout("Project.range: let modules: [\"\(result.package)\"]"))
            }
        }

        private func packageRow(
            reference: String,
            version: String,
            level: CLIStatusLevel
        ) -> String {
            let package = "\(reference)@latest"
            let width = max(32, package.count + 4)
            let padding = String(repeating: " ", count: max(1, width - package.count))
            return TerminalLog.style(package, level: level, bold: true)
                + padding
                + TerminalLog.subtleStdout(version)
        }

        private func runCloudSearchWithSpinner(query: String, searcher: PackageSearcher) throws
            -> [PackageSearchResult]
        {
            let box = PackageSearchResultBox()
            let thread = Thread {
                do {
                    box.store(.success(try searcher.search(query: query, limit: limit)))
                } catch {
                    box.store(.failure(error))
                }
            }
            thread.start()

            guard Platform.isTerminal(Platform.standardOutputFileDescriptor) else {
                while box.load() == nil {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                return try box.load()!.get()
            }

            let frames = ["|", "/", "-", "\\"]
            var index = 0
            while box.load() == nil {
                replaceCloudLines()
                renderCloudLoading(frame: frames[index % frames.count])
                index += 1
                Thread.sleep(forTimeInterval: 0.1)
            }

            return try box.load()!.get()
        }

        private func replaceCloudLines() {
            guard Platform.isTerminal(Platform.standardOutputFileDescriptor) else {
                return
            }

            fputs("\u{001B}[2A", stdout)
            fputs("\u{001B}[2K", stdout)
            fputs("\u{001B}[1B", stdout)
            fputs("\u{001B}[2K", stdout)
            fputs("\u{001B}[1A", stdout)
        }
    }
}

private final class PackageSearchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[PackageSearchResult], Error>?

    func store(_ result: Result<[PackageSearchResult], Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<[PackageSearchResult], Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
