import ArgumentParser
import Foundation

extension RangeCLI {
    struct Scripts: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage scripts saved under .range/.scripts.",
            subcommands: [
                Create.self,
                Save.self,
                List.self,
            ]
        )

        struct Create: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Create a starter script in .range/.scripts."
            )

            @Argument(help: "Script name. Adds .range when omitted.")
            var name: String

            @Option(name: .shortAndLong, help: "Package.range project root.")
            var project: String = "."

            @Flag(help: "Replace an existing script.")
            var force: Bool = false

            mutating func run() throws {
                do {
                    let url = try ProjectScriptStore(projectPath: project).create(name, force: force)
                    TerminalLog.out("Created script \(url.path)", level: .success)
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }

        struct Save: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Save text or a file into .range/.scripts."
            )

            @Argument(help: "Script name. Adds .range when omitted.")
            var name: String

            @Option(name: .shortAndLong, help: "Package.range project root.")
            var project: String = "."

            @Option(help: "Script content to save.")
            var content: String?

            @Option(name: .customLong("from"), help: "File to copy into the script store.")
            var sourcePath: String?

            @Flag(help: "Replace an existing script.")
            var force: Bool = false

            mutating func run() throws {
                do {
                    let source = try resolvedContent()
                    let url = try ProjectScriptStore(projectPath: project).save(
                        name,
                        content: source,
                        force: force
                    )
                    TerminalLog.out("Saved script \(url.path)", level: .success)
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }

            private func resolvedContent() throws -> String {
                if content != nil && sourcePath != nil {
                    throw ValidationError("Use either --content or --from, not both.")
                }
                if let content {
                    return content
                }
                if let sourcePath {
                    return try String(
                        contentsOf: URL(fileURLWithPath: sourcePath, isDirectory: false),
                        encoding: .utf8
                    )
                }
                throw ValidationError("Pass script text with --content or copy a file with --from.")
            }
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List scripts saved under .range/.scripts."
            )

            @Option(name: .shortAndLong, help: "Package.range project root.")
            var project: String = "."

            mutating func run() throws {
                do {
                    let scripts = try ProjectScriptStore(projectPath: project).list()
                    if scripts.isEmpty {
                        TerminalLog.subtleOut("Scripts: none")
                        return
                    }
                    for script in scripts {
                        print(script.lastPathComponent)
                    }
                } catch {
                    ErrorPresenter.printError(error)
                    throw ExitCode.failure
                }
            }
        }
    }
}
