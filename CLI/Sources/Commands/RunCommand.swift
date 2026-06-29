import ArgumentParser
import Foundation
import RangeEmission
import RangeCompiler

extension CLI {
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Emit, link, and run native LLVM output for a Range program."
        )

        @Argument(help: "Project directory or source .range file to run.")
        var input: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(requireManifestForDirectory: true)
                )
                let compiledProgram = try ProjectSourceValidator.compiledProgram(
                    for: project
                )
                let buildRoot = project.defaultBuildRoot
                if FileManager.default.fileExists(atPath: buildRoot.path) {
                    try FileManager.default.removeItem(at: buildRoot)
                }
                let irURL = buildRoot.appendingPathComponent("RangeScalar.ll")
                let emitter = CapabilityLLVMEmitter()
                _ = try emitter.emitModuleFile(
                    compiledProgram: compiledProgram,
                    outputURL: irURL
                )
                let executableURL = buildRoot.appendingPathComponent(project.packageName)
                let runner = NativeLLVMRunner()
                try runner.link(irURL: irURL, executableURL: executableURL)
                try runner.run(executableURL: executableURL)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
