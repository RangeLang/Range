import ArgumentParser
import Foundation
import NeatSyntax

enum NeatCoreLoader {
    static func coreFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coreRoot = root.appendingPathComponent("NeatSyntax/Sources/NeatCore", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: coreRoot.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ValidationError("Missing NeatCore sources at \(coreRoot.path)")
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: coreRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw ValidationError("Could not inspect NeatCore sources at \(coreRoot.path)")
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory, fileURL.pathExtension.lowercased() == "neat" else {
                continue
            }
            files.append(fileURL)
        }

        return files.sorted { $0.path < $1.path }
    }

    static func parsedDependencyFiles() throws -> [ParsedSourceFile] {
        try coreFiles().map { fileURL in
            ParsedSourceFile(
                path: fileURL.path,
                sourceFile: try ProjectSourceValidator.parseSourceFile(at: fileURL)
            )
        }
    }

    static func parsedValidationFiles() throws -> [ProjectSourceValidator.ParsedFile] {
        try coreFiles().map { fileURL in
            ProjectSourceValidator.ParsedFile(
                url: fileURL,
                sourceFile: try ProjectSourceValidator.parseSourceFile(at: fileURL)
            )
        }
    }
}
