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
        let coreRoot = root.appendingPathComponent("NeatCore", isDirectory: true)

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
            if isDirectory, fileURL.lastPathComponent == "Exploration",
                fileURL.path.contains("/NeatCore/")
            {
                enumerator.skipDescendants()
                continue
            }
            guard !isDirectory, fileURL.pathExtension.lowercased() == "neat" else {
                continue
            }
            files.append(fileURL)
        }

        return files.sorted { $0.path < $1.path }
    }

    static func sourceInputs() throws -> [SourceInput] {
        try coreFiles().map { fileURL in
            do {
                return SourceInput(
                    path: fileURL.path,
                    source: try String(contentsOf: fileURL, encoding: .utf8),
                    role: .core
                )
            } catch {
                throw ValidationError(
                    "Failed to read NeatCore file \(fileURL.lastPathComponent): \(error)"
                )
            }
        }
    }

    static func compiledProgram() throws -> CompiledProgram {
        try CompilerPipeline().build(inputs: sourceInputs())
    }

    static func parsedProgramFiles() throws -> [ParsedSourceFile] {
        try compiledProgram().parsedFiles
    }

    static func literalBridgeResolver() throws -> LiteralBridgeResolver {
        try compiledProgram().literalBridgeResolver
    }
}
