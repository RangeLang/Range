import ArgumentParser
import Foundation
import RangeCompiler

enum RangeCoreLoader {
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
            "Missing Range compiler core sources. Checked: \(candidates.map(\.path).joined(separator: ", "))"
        )
    }

    static func coreRoots() throws -> [URL] {
        let primaryRoot = try coreRoot()
        var roots = [primaryRoot]

        if primaryRoot.lastPathComponent == "Core" {
            let compilerRoot = primaryRoot.deletingLastPathComponent()
            let foundationRoot = compilerRoot
                .appendingPathComponent("Foundation", isDirectory: true)
                .standardizedFileURL
            if isExistingDirectory(foundationRoot) {
                roots.append(foundationRoot)
            }

            let lexerRoot = compilerRoot
                .appendingPathComponent("Lexer", isDirectory: true)
                .standardizedFileURL
            if isExistingDirectory(lexerRoot) {
                roots.append(lexerRoot)
            }
        }

        return roots
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func coreRootCandidates() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        let explicitPath = environment["RANGE_CORE_PATH"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        let executableURL = installedExecutableURL()
        let executableDirectory = executableURL.deletingLastPathComponent()
        let installedCompilerCoreRoot = executableDirectory
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        let legacyInstalledCompilerCoreRoot = executableDirectory
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        let installedCoreRoot = executableDirectory
            .appendingPathComponent("RangeCore", isDirectory: true)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceCompilerCoreRoot = repositoryRoot
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        let legacySourceCompilerCoreRoot = repositoryRoot
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        let sourceCoreRoot = repositoryRoot
            .appendingPathComponent("RangeCore", isDirectory: true)

        return [
            explicitPath,
            installedCompilerCoreRoot,
            legacyInstalledCompilerCoreRoot,
            installedCoreRoot,
            sourceCompilerCoreRoot,
            legacySourceCompilerCoreRoot,
            sourceCoreRoot,
        ].compactMap(\.self)
    }

    private static func installedExecutableURL() -> URL {
        let executable = CommandLine.arguments.first ?? "range"
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
        let filePath = fileURL.standardizedFileURL.path
        return try coreRoots().contains { coreRoot in
            let coreRootPath = coreRoot.path
            return filePath == coreRootPath || filePath.hasPrefix(coreRootPath + "/")
        }
    }

    static func coreFiles() throws -> [URL] {
        var files: [URL] = []
        for coreRoot in try coreRoots() {
            files.append(contentsOf: try coreFiles(in: coreRoot))
        }

        return files.sorted { $0.path < $1.path }
    }

    private static func coreFiles(in coreRoot: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: coreRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw ValidationError("Could not inspect Range compiler core sources at \(coreRoot.path)")
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory, fileURL.lastPathComponent == "Exploration",
                isCorePath(fileURL.path)
            {
                enumerator.skipDescendants()
                continue
            }
            guard !isDirectory, fileURL.pathExtension.lowercased() == "range" else {
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
                    "Failed to read Range compiler core file \(fileURL.lastPathComponent): \(ErrorDescription.message(for: error))"
                )
            }
        }
    }

    static func isCorePath(_ path: String) -> Bool {
        path.contains("/RangeCore/")
            || path.contains("/RangeCompiler/Range/Core/")
            || path.contains("/RangeCompiler/Range/Foundation/")
            || path.contains("/RangeCompiler/Range/Lexer/")
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
