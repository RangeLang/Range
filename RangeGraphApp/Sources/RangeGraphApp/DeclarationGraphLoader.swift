import Foundation
import RangeSyntax

enum DeclarationGraphLoader {
    static var defaultExampleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples/DeclarationGraphDemo", isDirectory: true)
    }

    static func load(from url: URL) throws -> DeclarationGraphDocument {
        let inputURL = url.standardizedFileURL
        let sourceFiles = try rangeFiles(at: inputURL)
        guard !sourceFiles.isEmpty else {
            throw LoaderError.noRangeFiles(inputURL.path)
        }

        let inputs = try sourceFiles.map { fileURL in
            SourceInput(
                path: fileURL.path,
                source: try String(contentsOf: fileURL, encoding: .utf8),
                role: .project
            )
        }
        let program = try CompilerPipeline().build(inputs: inputs)
        return DeclarationGraphDocument(
            title: title(for: inputURL),
            sourceRoot: inputURL,
            graph: .from(program.declarationGraph.programGraph)
        )
    }

    private static func title(for url: URL) -> String {
        if url.hasDirectoryPath {
            return url.lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func rangeFiles(at url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw LoaderError.missingInput(url.path)
        }

        if !isDirectory.boolValue {
            guard url.pathExtension.lowercased() == "range" else {
                throw LoaderError.notRangeInput(url.path)
            }
            return [url]
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw LoaderError.unreadableDirectory(url.path)
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if [".build", ".git", ".range"].contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard fileURL.pathExtension.lowercased() == "range" else {
                continue
            }
            if fileURL.lastPathComponent == "Package.range" {
                continue
            }
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }
}

enum LoaderError: LocalizedError {
    case missingInput(String)
    case notRangeInput(String)
    case unreadableDirectory(String)
    case noRangeFiles(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let path):
            return "Missing input at \(path)."
        case .notRangeInput(let path):
            return "Expected a .range file or a directory, got \(path)."
        case .unreadableDirectory(let path):
            return "Could not read directory \(path)."
        case .noRangeFiles(let path):
            return "No .range source files found in \(path)."
        }
    }
}
