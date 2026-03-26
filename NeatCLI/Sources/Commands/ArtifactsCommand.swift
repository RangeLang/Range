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
                let inputURL = URL(fileURLWithPath: input ?? ".").standardizedFileURL
                let files = try neatFiles(at: inputURL)
                let outputRoot = try outputRoot(for: inputURL)
                let renderer = CompilationArtifactsEmitter()

                try FileManager.default.createDirectory(
                    at: outputRoot,
                    withIntermediateDirectories: true
                )

                var parsedFiles: [ParsedSourceFile] = []

                for fileURL in files {
                    let source = try String(contentsOf: fileURL, encoding: .utf8)
                    let relativePath = try relativePath(for: fileURL, from: inputURL)
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
                        parsedFiles.append(
                            ParsedSourceFile(
                                path: fileURL.path,
                                sourceFile: try ProjectSourceValidator.parseSourceFile(at: fileURL)
                            )
                        )
                    } catch {
                        let message = """
                            Parse error:
                              \(error)
                            """
                        try message.write(
                            to: stageDirectory.appendingPathComponent("02-ast-error.txt"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                }

                let graphFiles = try NeatCoreLoader.parsedDependencyFiles() + parsedFiles
                let graph = renderer.renderGraph(files: graphFiles)
                try graph.write(
                    to: outputRoot.appendingPathComponent("03-graph.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                let graphHTML = renderer.renderGraphHTML(
                    files: graphFiles,
                    title: "Neat Playground Dependency Graph"
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

        private func outputRoot(for inputURL: URL) throws -> URL {
            if let output {
                return URL(fileURLWithPath: output).standardizedFileURL
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
            else {
                throw ValidationError("Missing input at \(inputURL.path)")
            }

            if isDirectory.boolValue {
                return inputURL.appendingPathComponent(".neat/Artifacts", isDirectory: true)
            }

            return inputURL.deletingLastPathComponent()
                .appendingPathComponent(".neat/Artifacts", isDirectory: true)
        }

        private func relativePath(for fileURL: URL, from inputURL: URL) throws -> String {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
            else {
                throw ValidationError("Missing input at \(inputURL.path)")
            }

            if isDirectory.boolValue {
                let rootPath = inputURL.path.hasSuffix("/") ? inputURL.path : inputURL.path + "/"
                let fullPath = fileURL.path
                if fullPath.hasPrefix(rootPath) {
                    let relative = String(fullPath.dropFirst(rootPath.count))
                    return relative.replacingOccurrences(of: ".neat", with: "")
                }
            }

            return fileURL.deletingPathExtension().lastPathComponent
        }

        private func neatFiles(at inputURL: URL) throws -> [URL] {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
            else {
                throw ValidationError("Missing input at \(inputURL.path)")
            }

            if !isDirectory.boolValue {
                guard inputURL.pathExtension.lowercased() == "neat" else {
                    throw ValidationError("Expected a .neat file or project directory.")
                }
                return [inputURL]
            }

            guard
                let enumerator = FileManager.default.enumerator(
                    at: inputURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )
            else {
                throw ValidationError("Could not inspect project files in \(inputURL.path)")
            }

            var files: [URL] = []

            while let fileURL = enumerator.nextObject() as? URL {
                let path = fileURL.path
                let isDirectory =
                    (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                    ?? false

                if path.contains("/.git/") || path.contains("/.build/")
                    || path.contains("/.neat/Build/") || path.contains("/.neat/Packages/")
                    || path.contains("/zed/neat/grammars/_stale_neat_checkout/")
                {
                    if isDirectory {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard !isDirectory, fileURL.pathExtension.lowercased() == "neat" else {
                    continue
                }

                files.append(fileURL)
            }

            return files.sorted { $0.path < $1.path }
        }
    }
}
