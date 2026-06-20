import ArgumentParser
import Foundation
import RangeEmission
import RangeCompiler

extension CLI {
    struct Compile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Emit LLVM IR for Range source files and projects."
        )

        @Argument(help: "Project directory or source .range file to validate.")
        var input: String?

        @Argument(help: "LLVM IR output path. Prints to stdout when omitted.")
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
                if let output {
                    let backend = SwiftBackend()
                    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
                    _ = try backend.emitLLVMIRFile(
                        project: SwiftBackendProject(
                            projectFiles: project.projectFiles,
                            isSingleFile: project.isSingleFile,
                            buildRoot: project.defaultBuildRoot
                        ),
                        compiledProgram: compiledProgram,
                        outputURL: outputURL
                    )
                    TerminalLog.out("Generated LLVM IR at \(output).", level: .success)
                } else {
                    let backend = SwiftBackend()
                    let ir = try backend.emitLLVMIR(
                        project: SwiftBackendProject(
                            projectFiles: project.projectFiles,
                            isSingleFile: project.isSingleFile,
                            buildRoot: project.defaultBuildRoot
                        ),
                        compiledProgram: compiledProgram
                    )
                    print(ir, terminator: "")
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
