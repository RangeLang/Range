import Foundation
import RangeCompiler
import RangeEmission

public struct SwiftBootstrapError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct SwiftBootstrapCompiler {
    public init() {}

    @discardableResult
    public func compileExecutable(rangeRoot: URL, input: URL) throws -> URL {
        let layout = try executableLayout(for: input)

        try? FileManager.default.removeItem(at: layout.buildRoot)
        try FileManager.default.createDirectory(
            at: layout.buildRoot,
            withIntermediateDirectories: true
        )

        try emitLLVM(rangeRoot: rangeRoot, input: input, output: layout.llvmIR)
        try linkExecutable(llvmIR: layout.llvmIR, executable: layout.executable)
        return layout.executable
    }

    @discardableResult
    public func run(rangeRoot: URL, input: URL, arguments: [String]) throws -> Int32 {
        let executable = try compileExecutable(rangeRoot: rangeRoot, input: input)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @discardableResult
    public func checkBootstrapCompiler(rangeRoot: URL, compilerDirectory: URL) throws -> URL {
        let executable = try compileExecutable(rangeRoot: rangeRoot, input: compilerDirectory)
        let mainInput = compilerDirectory.appendingPathComponent("Main.range")
        let mainResult = try runExecutable(executable: executable, arguments: [mainInput.path], stdin: nil)
        guard mainResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler exited \(mainResult.exitCode): \(mainInput.path)
                --- stdout ---
                \(prefixLines(mainResult.stdout))
                --- stderr ---
                \(prefixLines(mainResult.stderr))
                """
            )
        }
        guard mainResult.stdout.contains("macroAttribute\\t@main"),
            mainResult.stdout.contains("identifier\\tcommandLineArgumentCount"),
            mainResult.stdout.contains("keyword\\treturn"),
            mainResult.stdout.contains("parse\\tmainBlock")
        else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler did not scan expected entrypoint tokens: \(mainInput.path)
                --- stdout ---
                \(prefixLines(mainResult.stdout))
                --- stderr ---
                \(prefixLines(mainResult.stderr))
                """
            )
        }

        let lexerInput = compilerDirectory.appendingPathComponent("Lexer.range")
        let lexerResult = try runExecutable(executable: executable, arguments: [lexerInput.path], stdin: nil)
        guard lexerResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler exited \(lexerResult.exitCode): \(lexerInput.path)
                --- stdout ---
                \(prefixLines(lexerResult.stdout))
                --- stderr ---
                \(prefixLines(lexerResult.stderr))
                """
            )
        }
        guard lexerResult.stdout.contains("keyword\\tconstruct"),
            lexerResult.stdout.contains("identifier\\tRangeLexedToken"),
            lexerResult.stdout.contains("identifier\\tlexNextRangeToken"),
            lexerResult.stdout.contains("stringLiteral\\t\"ellipsis\""),
            lexerResult.stdout.contains("parse\\tnoMainBlock")
        else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler did not scan expected lexer tokens: \(lexerInput.path)
                --- stdout ---
                \(prefixLines(lexerResult.stdout))
                --- stderr ---
                \(prefixLines(lexerResult.stderr))
                """
            )
        }
        print("Bootstrap compiler check succeeded: \(executable.path)")
        return executable
    }

    @discardableResult
    public func checkLLVMRuns(
        rangeRoot: URL,
        manifest: URL,
        requireFullCoverage: Bool
    ) throws -> Int {
        let manifestEntries = try parseRunManifest(manifest)
        if manifestEntries.isEmpty {
            throw SwiftBootstrapError("LLVM run manifest has no runnable entries: \(manifest.path)")
        }

        try validateManifestCoverage(
            entries: manifestEntries,
            manifest: manifest,
            requireFullCoverage: requireFullCoverage
        )

        var count = 0
        for entry in manifestEntries {
            count += 1
            print("[\(count)] run \(entry.source.lastPathComponent)")
            let executable = try compileExecutable(rangeRoot: rangeRoot, input: entry.source)
            let result = try runExecutable(
                executable: executable,
                arguments: entry.arguments,
                stdin: entry.stdin
            )

            if result.exitCode != entry.expectedExit {
                throw SwiftBootstrapError(
                    """
                    Expected exit \(entry.expectedExit), got \(result.exitCode) for \(entry.source.path)
                    --- stdout ---
                    \(prefixLines(result.stdout))
                    --- stderr ---
                    \(prefixLines(result.stderr))
                    """
                )
            }

            if let expectedStdout = entry.expectedStdout, result.stdout != expectedStdout {
                throw SwiftBootstrapError(
                    """
                    Stdout mismatch for \(entry.source.path)
                    --- expected stdout ---
                    \(prefixLines(expectedStdout))
                    --- actual stdout ---
                    \(prefixLines(result.stdout))
                    --- stderr ---
                    \(prefixLines(result.stderr))
                    """
                )
            }
        }

        print("LLVM run checks succeeded for \(count) example(s).")
        return count
    }

    @discardableResult
    public func checkLLVMExamples(rangeRoot: URL, examplesDirectory: URL) throws -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: examplesDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SwiftBootstrapError("Missing LLVM examples directory: \(examplesDirectory.path)")
        }

        let examples = try topLevelRangeFiles(in: examplesDirectory)
        if examples.isEmpty {
            throw SwiftBootstrapError("No LLVM examples found in: \(examplesDirectory.path)")
        }

        let buildRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-llvm-examples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: buildRoot)
        }

        for (index, input) in examples.enumerated() {
            let count = index + 1
            let output = buildRoot
                .appendingPathComponent(input.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("ll")
            print("[\(count)] emit \(input.lastPathComponent)")
            try emitLLVM(rangeRoot: rangeRoot, input: input, output: output)
        }

        print("LLVM emission succeeded for \(examples.count) example(s).")
        return examples.count
    }

    public func emitLLVM(rangeRoot: URL, input: URL, output: URL) throws {
        let inputs = try coreInputs(rangeRoot: rangeRoot) + projectInputs(input: input)
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let module = try LLVMModuleEmitter().emit(program: program)

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try module.write(to: output, atomically: true, encoding: .utf8)
    }

    private func rangeFiles(in root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw SwiftBootstrapError("Missing directory: \(root.path)")
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                switch url.lastPathComponent {
                case ".build", ".git", ".range":
                    enumerator.skipDescendants()
                default:
                    break
                }
                continue
            }

            guard url.pathExtension.lowercased() == "range" else {
                continue
            }
            files.append(url)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func topLevelRangeFiles(in directory: URL) throws -> [URL] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw SwiftBootstrapError("Missing directory: \(directory.path)")
        }

        return try urls.filter { url in
            let isRegularFile =
                try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
            return isRegularFile && url.pathExtension.lowercased() == "range"
        }
        .sorted { $0.path < $1.path }
    }

    private func sourceInput(for file: URL, role: SourceInputRole) throws -> SourceInput {
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: role
        )
    }

    private func coreInputs(rangeRoot: URL) throws -> [SourceInput] {
        let roots = [
            rangeRoot.appendingPathComponent("Core", isDirectory: true),
            rangeRoot.appendingPathComponent("Foundation", isDirectory: true),
            rangeRoot.appendingPathComponent("Lexer", isDirectory: true),
        ]

        return try roots.flatMap { root in
            try rangeFiles(in: root).map { try sourceInput(for: $0, role: .core) }
        }
    }

    private func projectInputs(input: URL) throws -> [SourceInput] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw SwiftBootstrapError("Missing input: \(input.path)")
        }

        if isDirectory.boolValue {
            return try rangeFiles(in: input).map { try sourceInput(for: $0, role: .project) }
        }

        return [try sourceInput(for: input, role: .project)]
    }

    private func executableLayout(for input: URL) throws -> ExecutableLayout {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw SwiftBootstrapError("Missing input: \(input.path)")
        }

        let projectRoot: URL
        let executableName: String
        if isDirectory.boolValue {
            projectRoot = input
            executableName = input.lastPathComponent
        } else {
            projectRoot = input.deletingLastPathComponent()
            executableName = input.deletingPathExtension().lastPathComponent
        }

        let buildRoot = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("llvm", isDirectory: true)

        return ExecutableLayout(
            buildRoot: buildRoot,
            llvmIR: buildRoot.appendingPathComponent("Main.ll"),
            executable: buildRoot.appendingPathComponent(executableName)
        )
    }

    private func linkExecutable(llvmIR: URL, executable: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "clang",
            "-Wno-override-module",
            llvmIR.path,
            "-o",
            executable.path,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stdoutText = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let details = [stderrText, stdoutText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if details.isEmpty {
                throw SwiftBootstrapError("clang failed with exit \(process.terminationStatus).")
            }
            throw SwiftBootstrapError(details)
        }
    }

    private func parseRunManifest(_ manifest: URL) throws -> [RunManifestEntry] {
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw SwiftBootstrapError("Missing LLVM run manifest: \(manifest.path)")
        }

        let manifestDirectory = manifest.deletingLastPathComponent()
        let text = try String(contentsOf: manifest, encoding: .utf8)
        var entries: [RunManifestEntry] = []

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
        {
            let lineNumber = index + 1
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
            guard columns.count >= 4 else {
                throw SwiftBootstrapError(
                    "Invalid manifest row \(lineNumber) in \(manifest.path): expected at least file, exit, stdin, and args columns."
                )
            }

            guard let expectedExit = Int32(columns[1]), expectedExit >= 0, expectedExit <= 255 else {
                throw SwiftBootstrapError(
                    "Invalid expected exit '\(columns[1])' on manifest row \(lineNumber) in \(manifest.path)."
                )
            }

            let source = sourceURL(for: columns[0], relativeTo: manifestDirectory)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw SwiftBootstrapError(
                    "Manifest row \(lineNumber) references missing source: \(source.path)"
                )
            }

            entries.append(
                RunManifestEntry(
                    source: source,
                    expectedExit: expectedExit,
                    stdin: columns[2] == "-" ? nil : decodeManifestEscapes(columns[2]),
                    arguments: columns[3] == "-" ? [] : shellLikeArguments(columns[3]),
                    expectedStdout: columns.count > 4 && columns[4] != "-"
                        ? decodeManifestEscapes(columns[4])
                        : nil
                )
            )
        }

        return entries
    }

    private func validateManifestCoverage(
        entries: [RunManifestEntry],
        manifest: URL,
        requireFullCoverage: Bool
    ) throws {
        let manifestNames = entries.map { $0.source.lastPathComponent }
        let duplicateNames = Dictionary(grouping: manifestNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        if !duplicateNames.isEmpty {
            throw SwiftBootstrapError(
                "Duplicate LLVM run manifest entries:\n\(duplicateNames.prefix(80).joined(separator: "\n"))"
            )
        }

        guard requireFullCoverage else {
            return
        }

        let manifestDirectory = manifest.deletingLastPathComponent()
        let corpusNames = try rangeFiles(in: manifestDirectory)
            .filter { $0.deletingLastPathComponent() == manifestDirectory }
            .map(\.lastPathComponent)
            .sorted()
        let manifestNameSet = Set(manifestNames)
        let corpusNameSet = Set(corpusNames)
        let missingNames = corpusNames.filter { !manifestNameSet.contains($0) }
        if !missingNames.isEmpty {
            throw SwiftBootstrapError(
                "LLVM run manifest is missing example(s):\n\(missingNames.prefix(120).joined(separator: "\n"))"
            )
        }

        let extraNames = manifestNames.sorted().filter { !corpusNameSet.contains($0) }
        if !extraNames.isEmpty {
            throw SwiftBootstrapError(
                "LLVM run manifest references non-corpus example(s):\n\(extraNames.prefix(120).joined(separator: "\n"))"
            )
        }
    }

    private func sourceURL(for path: String, relativeTo directory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return directory.appendingPathComponent(path)
    }

    private func runExecutable(
        executable: URL,
        arguments: [String],
        stdin: String?
    ) throws -> ExecutionResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdinPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            stdinPipe = nil
        }

        try process.run()

        if let stdinPipe, let stdin {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        let stdoutText = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderrText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return ExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
    }
}

private struct ExecutableLayout {
    var buildRoot: URL
    var llvmIR: URL
    var executable: URL
}

private struct RunManifestEntry {
    var source: URL
    var expectedExit: Int32
    var stdin: String?
    var arguments: [String]
    var expectedStdout: String?
}

private struct ExecutionResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private func shellLikeArguments(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
}

private func decodeManifestEscapes(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
        let character = text[index]
        guard character == "\\" else {
            result.append(character)
            index = text.index(after: index)
            continue
        }

        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex else {
            result.append(character)
            index = nextIndex
            continue
        }

        switch text[nextIndex] {
        case "n":
            result.append("\n")
        case "r":
            result.append("\r")
        case "t":
            result.append("\t")
        case "\\":
            result.append("\\")
        default:
            result.append(text[nextIndex])
        }
        index = text.index(after: nextIndex)
    }
    return result
}

private func prefixLines(_ text: String, limit: Int = 80) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        .prefix(limit)
        .map(String.init)
    return lines.joined(separator: "\n")
}
