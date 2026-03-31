import ArgumentParser
import Foundation
import NeatSyntax

extension NeatCLI {
    struct Compile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate Neat source files and projects."
        )

        @Argument(help: "Project directory or source .neat file to validate.")
        var input: String?

        @Argument(help: "Reserved for future target output.")
        var output: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(requireManifestForDirectory: true)
                )
                let semanticProgram = try ProjectSourceValidator.validatedSemanticProgram(
                    for: project
                )
                let backend = BackendRegistry.default()
                if let output {
                    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
                    _ = try backend.emitSourceFile(
                        project: project,
                        semanticProgram: semanticProgram,
                        outputURL: outputURL
                    )
                    TerminalLog.out("Generated Swift at \(output).", level: .success)
                } else {
                    let workspace = try backend.emitWorkspace(
                        project: project,
                        semanticProgram: semanticProgram
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
