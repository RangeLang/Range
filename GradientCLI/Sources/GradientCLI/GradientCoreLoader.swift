import ArgumentParser
import Foundation
import NeatSyntax

enum NeatCoreLoader {
    static func coreRoot() throws -> URL {
        let candidates = coreRootCandidates()
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return candidate.standardizedFileURL
            }
        }

        throw ValidationError(
            "Missing NeatCore sources. Checked: \(candidates.map(\.path).joined(separator: ", "))"
        )
    }

    private static func coreRootCandidates() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        let explicitPath = environment["NEAT_CORE_PATH"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        let executableURL = installedExecutableURL()
        let executableDirectory = executableURL.deletingLastPathComponent()
        let installShareRoot = executableDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("share/neat/NeatCore", isDirectory: true)

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NeatCore", isDirectory: true)

        return [explicitPath, installShareRoot, sourceRoot].compactMap(\.self)
    }

    private static func installedExecutableURL() -> URL {
        let executable = CommandLine.arguments.first ?? "neat"
        if executable.contains("/") {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        guard let lookupTool = Platform.defaultExecutableLookupTool else {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        let process = Process()
        process.executableURL = lookupTool
        process.arguments = ["which", executable]
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return URL(fileURLWithPath: path).standardizedFileURL
                }
            }
        } catch {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        return URL(fileURLWithPath: executable).standardizedFileURL
    }

    static func isCoreFile(_ fileURL: URL) throws -> Bool {
        let coreRootPath = try coreRoot().path
        let filePath = fileURL.standardizedFileURL.path
        return filePath == coreRootPath || filePath.hasPrefix(coreRootPath + "/")
    }

    static func coreFiles() throws -> [URL] {
        let coreRoot = try coreRoot()

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
                    "Failed to read NeatCore file \(fileURL.lastPathComponent): \(ErrorDescription.message(for: error))"
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
