import ArgumentParser
import Foundation

extension NeatCLI {
    struct Package: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage installed Neat packages.",
            subcommands: [
                Publish.self,
                Subscribe.self
            ]
        )

        @Option(
            name: .customLong("project"),
            help: "Project directory. Defaults to current directory."
        )
        var path: String = "."

        mutating func run() throws {
            do {
                let packageFile = URL(fileURLWithPath: path, isDirectory: true)
                    .standardizedFileURL
                    .appendingPathComponent("Package.neat", isDirectory: false)
                let manifest = try PackageManifestLoader.load(from: packageFile)

                print(TerminalLog.style(manifest.name, level: .change, bold: true))
                print("Version: \(manifest.version ?? "unknown")")
                print("Author: \(manifest.author ?? "unknown")")
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        struct Publish: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Publish this package with a semantic version bump."
            )

            @Argument(help: "Version bump to publish: major, minor, or patch.")
            var bump: PackageVersionBump

            @Option(
                name: [.short, .customLong("path")],
                help: "Project directory. Defaults to current directory."
            )
            var projectPath: String = "."

            mutating func run() throws {
                do {
                    let publisher = PackagePublisher(projectPath: projectPath)
                    let published = try publisher.publish(bump)
                    TerminalLog.out(
                        "Published \(published.name) \(published.version).",
                        level: .success
                    )
                    if let author = published.author, !author.isEmpty {
                        TerminalLog.subtleOut("Author: \(author)")
                    }
                    TerminalLog.subtleOut("Package.neat: \(published.packageFile.path)")
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }

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
