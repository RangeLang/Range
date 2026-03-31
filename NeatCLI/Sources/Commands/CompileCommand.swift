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
                let driver = SwiftBackendDriver()
                if let output {
                    try driver.emitSwiftSource(
                        project: project,
                        semanticProgram: semanticProgram,
                        to: output
                    )
                    TerminalLog.out("Generated Swift at \(output).", level: .success)
                } else {
                    let buildRoot = try driver.emitProjectWorkspace(
                        project: project,
                        semanticProgram: semanticProgram
                    )
                    TerminalLog.out(
                        "Generated Swift workspace at \(buildRoot.path).",
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
