import ArgumentParser
import Foundation
import RangeEmission
import RangeCompiler

extension CLI {
    struct Compile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate Range source files and emit a native LLVM runner script."
        )

        @Argument(help: "Project directory or source .range file to validate.")
        var input: String?

        @Argument(help: "Runner script output path. Prints to stdout when omitted.")
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
                let emitter = CapabilityLLVMEmitter()
                let script = validationScript(for: emitter.emitModule(compiledProgram: compiledProgram).ir)
                if let output {
                    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
                    try FileManager.default.createDirectory(
                        at: outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try script.write(to: outputURL, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: outputURL.path
                    )
                    TerminalLog.out("Generated validation script at \(output).", level: .success)
                } else {
                    print(script, terminator: "")
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func validationScript(for ir: String) -> String {
            let delimiter = heredocDelimiter(for: ir)
            return """
                #!/usr/bin/env bash
                set -euo pipefail

                SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                IR_FILE="${RANGE_LLVM_IR_FILE:-$SCRIPT_DIR/RangeScalar.ll}"
                EXECUTABLE="${RANGE_EXECUTABLE:-$SCRIPT_DIR/Compiler}"

                mkdir -p "$(dirname "$IR_FILE")"
                cat > "$IR_FILE" <<'\(delimiter)'
                \(ir)
                \(delimiter)

                clang "$IR_FILE" -o "$EXECUTABLE"
                "$EXECUTABLE" "$@"
                """
        }

        private func heredocDelimiter(for text: String) -> String {
            var delimiter = "__RANGE_LLVM_IR__"
            while text.contains(delimiter) {
                delimiter += "_END"
            }
            return delimiter
        }
    }
}
