import ArgumentParser
import Foundation

extension NeatCLI {
    struct Package: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage installed Neat packages.",
            subcommands: [
                Patch.self,
                Minor.self,
                Major.self,
                Publish.self,
                List.self,
                Search.self,
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
                print("Version: \(manifest.version)")
                print("Author: \(manifest.author)")
                if manifest.remoteURLs.isEmpty {
                    print("Remotes: unknown")
                } else {
                    print("Remotes:")
                    for remoteURL in manifest.remoteURLs {
                        print("  \(remoteURL)")
                    }
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private static func publish(
            bump: PackageVersionBump,
            projectPath: String,
            noGit: Bool,
            noPush: Bool
        ) throws {
            let publisher = PackagePublisher(projectPath: projectPath)
            let published = try publisher.publish(
                bump,
                automateGit: !noGit,
                push: !noPush
            )
            TerminalLog.out(
                "Published \(published.name) \(published.version).",
                level: .success
            )
            if !published.author.isEmpty {
                TerminalLog.subtleOut("Author: \(published.author)")
            }
            TerminalLog.subtleOut("Package.neat: \(published.packageFile.path)")
            switch published.git {
            case .published(let commit, let tag, let pushed):
                TerminalLog.subtleOut("Git: \(commit), \(tag)\(pushed ? ", pushed" : ", not pushed")")
            case .skipped(let reason):
                TerminalLog.subtleOut("Git: skipped (\(reason))")
            }
        }

        struct Patch: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Publish this package with a patch version bump."
            )

            @Option(name: [.short, .customLong("path")], help: "Project directory. Defaults to current directory.")
            var projectPath: String = "."

            @Flag(help: "Only bump Package.neat; do not commit or tag.")
            var noGit: Bool = false

            @Flag(help: "Commit and tag locally, but do not push to origin.")
            var noPush: Bool = false

            mutating func run() throws {
                do {
                    try Package.publish(
                        bump: .patch,
                        projectPath: projectPath,
                        noGit: noGit,
                        noPush: noPush
                    )
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }

        struct Minor: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Publish this package with a minor version bump."
            )

            @Option(name: [.short, .customLong("path")], help: "Project directory. Defaults to current directory.")
            var projectPath: String = "."

            @Flag(help: "Only bump Package.neat; do not commit or tag.")
            var noGit: Bool = false

            @Flag(help: "Commit and tag locally, but do not push to origin.")
            var noPush: Bool = false

            mutating func run() throws {
                do {
                    try Package.publish(
                        bump: .minor,
                        projectPath: projectPath,
                        noGit: noGit,
                        noPush: noPush
                    )
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }

        struct Major: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Publish this package with a major version bump."
            )

            @Option(name: [.short, .customLong("path")], help: "Project directory. Defaults to current directory.")
            var projectPath: String = "."

            @Flag(help: "Only bump Package.neat; do not commit or tag.")
            var noGit: Bool = false

            @Flag(help: "Commit and tag locally, but do not push to origin.")
            var noPush: Bool = false

            mutating func run() throws {
                do {
                    try Package.publish(
                        bump: .major,
                        projectPath: projectPath,
                        noGit: noGit,
                        noPush: noPush
                    )
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
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

            @Flag(help: "Only bump Package.neat; do not commit or tag.")
            var noGit: Bool = false

            @Flag(help: "Commit and tag locally, but do not push to origin.")
            var noPush: Bool = false

            mutating func run() throws {
                do {
                    try Package.publish(
                        bump: bump,
                        projectPath: projectPath,
                        noGit: noGit,
                        noPush: noPush
                    )
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List packages from a machine or project scope."
            )

            @Argument(help: "Package scope to list: machine or project.")
            var scope: PackageListScope

            @Argument(
                parsing: .remaining,
                help: "Optional search terms."
            )
            var terms: [String] = []

            @Option(
                name: [.short, .customLong("path")],
                help: "Project directory for project package listings. Defaults to current directory."
            )
            var path: String = "."

            mutating func run() throws {
                do {
                    try PackageListRenderer.render(scope: scope, projectPath: path, terms: terms)
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
