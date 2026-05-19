import ArgumentParser
import Foundation
import RangeSyntax

extension RangeCLI {
    struct Compile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate Range source files and projects."
        )

        @Argument(help: "Project directory or source .range file to validate.")
        var input: String?

        @Argument(help: "Reserved for future target output.")
        var output: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(requireManifestForDirectory: true)
                )
                let compiledProgram = try ProjectSourceValidator.validatedCompiledProgram(
                    for: project
                )
                let backend = BackendRegistry.default()
                if let output {
                    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
                    _ = try backend.emitSourceFile(
                        project: project,
                        compiledProgram: compiledProgram,
                        outputURL: outputURL
                    )
                    TerminalLog.out("Generated Swift at \(output).", level: .success)
                } else {
                    let workspace = try backend.emitWorkspace(
                        project: project,
                        compiledProgram: compiledProgram
                    )
                    TerminalLog.out(
                        "Generated Swift workspace at \(workspace.root.path).",
                        level: .success
                    )
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
