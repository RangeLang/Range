import ArgumentParser
import Foundation
import NeatSyntax

extension NeatCLI {
    struct Compile: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compile a .neat project or a single .neat component."
        )

        @Argument(help: "Project directory or source .neat file.")
        var input: String?

        @Argument(help: "Output JavaScript file for single-file component compilation.")
        var output: String?

        mutating func run() throws {
            do {
                switch (input, output) {
                case (.some(let input), .some(let output)):
                    try compileSingleFile(input: input, output: output)
                case (.some(let input), nil):
                    let compiler = ProjectCompiler(path: input)
                    try compiler.run()
                case (nil, nil):
                    let compiler = ProjectCompiler(path: ".")
                    try compiler.run()
                case (nil, .some):
                    throw ValidationError("Single-file compilation requires both input and output.")
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func compileSingleFile(input: String, output: String) throws {
            let inputURL = URL(fileURLWithPath: input)
            let source = try String(contentsOf: inputURL, encoding: .utf8)
            let annotated = annotateDebugPrints(
                in: source,
                fileName: inputURL.lastPathComponent
            )
            var parser = try Parser(source: annotated)
            let component = try parser.parseComponent()
            let compiled = JavaScriptGenerator().generate(component: component)

            let outputURL = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try compiled.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)
        }

        private func annotateDebugPrints(in source: String, fileName: String) -> String {
            let lines = source.components(separatedBy: .newlines)
            var result: [String] = []
            result.reserveCapacity(lines.count)

            for (index, rawLine) in lines.enumerated() {
                let lineNumber = index + 1
                let prefix = "[\(fileName):\(lineNumber)] "

                if let range = rawLine.range(of: "#print(\"") {
                    var line = rawLine
                    line.replaceSubrange(range, with: "print(\"\(prefix)")
                    result.append(line)
                    continue
                }

                if let range = rawLine.range(of: "print(\"") {
                    var line = rawLine
                    line.replaceSubrange(range, with: "print(\"\(prefix)")
                    result.append(line)
                    continue
                }

                result.append(rawLine)
            }

            return result.joined(separator: "\n")
        }
    }
}
