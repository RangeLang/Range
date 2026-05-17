import ArgumentParser
import Foundation
import NeatSyntax

extension NeatCLI {
    struct Artifacts: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write lexer, parser, and graph artifacts for a Neat file or project."
        )

        @Argument(help: "Project directory or source .neat file to inspect.")
        var input: String?

        @Option(
            name: .shortAndLong,
            help: "Output directory. Defaults to .neat/Artifacts inside the input root."
        )
        var output: String?

        mutating func run() throws {
            do {
                let project = try ProjectLoader.load(
                    at: input ?? ".",
                    options: .init(
                        excludedPathFragments: ["/Zed/Neat/grammars/_stale_neat_checkout/"]
                    )
                )
                let outputRoot =
                    output.map {
                        URL(fileURLWithPath: $0).standardizedFileURL
                    } ?? project.defaultArtifactsRoot
                let renderer = CompilationArtifactsEmitter()

                try FileManager.default.createDirectory(
                    at: outputRoot,
                    withIntermediateDirectories: true
                )

                let compiledProgram = try ProjectSourceValidator.compiledProgram(for: project)
                let expandedByPath = Dictionary(
                    uniqueKeysWithValues: compiledProgram.projectExpandedFiles.map {
                        ($0.path, $0.sourceFile)
                    }
                )

                for fileURL in project.projectFiles {
                    let source = try String(contentsOf: fileURL, encoding: .utf8)
                    let relativePath = project.relativeOutputPath(for: fileURL)
                    let stageDirectory = outputRoot.appendingPathComponent(
                        relativePath, isDirectory: true)

                    try FileManager.default.createDirectory(
                        at: stageDirectory,
                        withIntermediateDirectories: true
                    )

                    let tokens = try renderer.renderTokens(source: source)
                    try tokens.write(
                        to: stageDirectory.appendingPathComponent("01-tokens.txt"),
                        atomically: true,
                        encoding: .utf8
                    )

                    do {
                        let ast = try renderer.renderAST(source: source)
                        try ast.write(
                            to: stageDirectory.appendingPathComponent("02-ast.txt"),
                            atomically: true,
                            encoding: .utf8
                        )
                        guard let expandedSourceFile = expandedByPath[fileURL.path] else {
                            throw ValidationError("Failed to expand \(fileURL.lastPathComponent).")
                        }
                        _ = expandedSourceFile
                    } catch {
                        let message = """
                            Parse error:
                              \(ErrorDescription.message(for: error))
                            """
                        try message.write(
                            to: stageDirectory.appendingPathComponent("02-ast-error.txt"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                }

                let graph = renderer.renderGraph(files: compiledProgram.expandedFiles)
                try graph.write(
                    to: outputRoot.appendingPathComponent("03-graph.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                let graphHTML = renderer.renderGraphHTML(
                    files: compiledProgram.expandedFiles,
                    title: "Neat Playground Application Graph"
                )
                try graphHTML.write(
                    to: outputRoot.appendingPathComponent("04-graph.html"),
                    atomically: true,
                    encoding: .utf8
                )

                TerminalLog.out("Wrote artifacts to \(outputRoot.path).", level: .success)
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }
    }
}
