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
                let driver = SwiftBackendDriver()
                switch (input, output) {
                case (.some(let input), .some(let output)):
                    try driver.emitSwiftSource(at: input, to: output)
                    TerminalLog.out("Generated Swift at \(output).", level: .success)
                case (.some(let input), nil):
                    let buildRoot = try driver.emitProjectWorkspace(at: input)
                    TerminalLog.out(
                        "Generated Swift workspace at \(buildRoot.path).",
                        level: .success
                    )
                case (nil, nil):
                    let buildRoot = try driver.emitProjectWorkspace(at: ".")
                    TerminalLog.out(
                        "Generated Swift workspace at \(buildRoot.path).",
                        level: .success
                    )
                case (nil, .some(let output)):
                    try driver.emitSwiftSource(at: ".", to: output)
                    TerminalLog.out("Generated Swift at \(output).", level: .success)
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
