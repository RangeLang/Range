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
                switch (input, output) {
                case (.some, .some(let output)):
                    throw ValidationError(
                        "Output generation is unavailable until a target backend is linked. Received output path \(output)."
                    )
                case (.some(let input), nil):
                    try compileProject(at: input)
                case (nil, nil):
                    try compileProject(at: ".")
                case (nil, .some):
                    throw ValidationError(
                        "Output generation is unavailable until a target backend is linked.")
                }
            } catch {
                ErrorPresenter.printError(error)
                throw ExitCode.failure
            }
        }

        private func compileProject(at path: String) throws {
            let inputURL = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
            else {
                throw ValidationError("Missing input at \(inputURL.path)")
            }

            if isDirectory.boolValue {
                let projectRoot = inputURL
                let packageFile = projectRoot.appendingPathComponent(
                    "Package.neat", isDirectory: false)
                guard FileManager.default.fileExists(atPath: packageFile.path) else {
                    throw ValidationError("Missing Package.neat in \(projectRoot.path)")
                }
                _ = try PackageManifestLoader.load(from: packageFile)

                let files = try neatFiles(in: projectRoot)
                guard !files.isEmpty else {
                    throw ValidationError("No .neat source files found in \(projectRoot.path)")
                }

                for file in files {
                    try validateFile(at: file)
                }

                Swift.print("Validated \(files.count) Neat source file(s).")
                return
            }

            guard inputURL.pathExtension.lowercased() == "neat" else {
                throw ValidationError("Expected a .neat file or project directory.")
            }
            try validateFile(at: inputURL)
            Swift.print("Validated \(inputURL.lastPathComponent).")
        }

        private func validateFile(at fileURL: URL) throws {
            if fileURL.lastPathComponent == "Package.neat" {
                _ = try PackageManifestLoader.load(from: fileURL)
                return
            }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            var parser = try Parser(source: source)
            _ = try parser.parseSourceFile()
        }

        private func neatFiles(in root: URL) throws -> [URL] {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            else {
                throw ValidationError("Could not inspect project files in \(root.path)")
            }

            var files: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let isDirectory =
                    (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                    ?? false

                if isDirectory {
                    if fileURL.lastPathComponent == ".git"
                        || fileURL.lastPathComponent == ".build"
                        || fileURL.lastPathComponent == ".neat"
                    {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard fileURL.pathExtension.lowercased() == "neat" else {
                    continue
                }
                if fileURL.lastPathComponent == "Package.neat" {
                    continue
                }
                files.append(fileURL)
            }

            return files.sorted { $0.path < $1.path }
        }
    }
}
