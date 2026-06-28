import ArgumentParser
import Foundation
import RangeCompiler

extension CLI {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate a Range project through the current emission pipeline."
        )

        @Argument(help: "Project directory or source .range file to build.")
        var input: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(requireManifestForDirectory: true)
                )
                let program = try ProjectSourceValidator.compiledProgram(for: project)
                try checkMainBlock(program: program)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func checkMainBlock(program: CompiledProgram) throws {
            let mainCount = program.projectExpandedFiles.reduce(0) { count, file in
                count + mainBlockCount(in: file.sourceFile)
            }

            if mainCount == 0 {
                TerminalLog.out("Range build requires exactly one @main block.", level: .error)
                throw ValidationError("Range build failed.")
            }

            if mainCount > 1 {
                TerminalLog.out(
                    "A second @main conflicts with the main block already declared in this Range project.",
                    level: .error
                )
                throw ValidationError("Range build failed.")
            }

            TerminalLog.out("Range build checked project source.", level: .success)
        }

        private func mainBlockCount(in sourceFile: ModuleFileNode) -> Int {
            sourceFile.blockMacros.filter { $0.macros.first?.name == "main" }.count
        }
    }
}
