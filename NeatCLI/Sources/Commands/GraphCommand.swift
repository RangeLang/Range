import ArgumentParser
import Foundation
import NeatSyntax

extension NeatCLI {
    struct Graph: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build and print the structural dependency graph for a Neat file or project."
        )

        @Argument(help: "Project directory or source .neat file to inspect.")
        var input: String?

        mutating func run() throws {
            do {
                let inputURL = URL(fileURLWithPath: input ?? ".").standardizedFileURL
                let files = try graphFiles(at: inputURL)
                let parsedFiles = try files.map { fileURL in
                    ParsedSourceFile(
                        path: fileURL.path,
                        sourceFile: try ProjectSourceValidator.parseSourceFile(at: fileURL)
                    )
                }

                let graph = DependencyGraphBuilder().build(files: parsedFiles)
                print(graph.render())
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func graphFiles(at inputURL: URL) throws -> [URL] {
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
