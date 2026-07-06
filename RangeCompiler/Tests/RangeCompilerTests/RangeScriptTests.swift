import Foundation
@testable import RangeCompiler
import Testing

@Suite("Range script", .serialized)
struct RangeScriptTests {
    @Test("Default run manifest covers every LLVM example")
    func defaultRunManifestCoversEveryLLVMExample() throws {
        let examplesDirectory = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM", isDirectory: true)
        let manifest = examplesDirectory.appendingPathComponent("run-manifest.tsv")
        let exampleNames = try rangeExampleNames(in: examplesDirectory)
        let manifestNames = try runManifestNames(in: manifest)

        #expect(manifestNames.count == 148)
        #expect(manifestNames == exampleNames)
    }

    @Test("Check command rejects unexpected arguments")
    func checkCommandRejectsUnexpectedArguments() throws {
        let result = try runRangeScript(arguments: ["check", "extra"])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("scripts/range check"))
    }

    @Test("Run manifest rejects empty manifests")
    func runManifestRejectsEmptyManifests() throws {
        let manifest = try temporaryManifest(contents: "")
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("LLVM run manifest has no runnable entries"))
    }

    @Test("Run manifest rejects duplicate entries")
    func runManifestRejectsDuplicateEntries() throws {
        let example = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/EmptyMain.range")
        let manifest = try temporaryManifest(
            contents: """
            \(example.path)\t0\t-\t-\t-
            \(example.path)\t0\t-\t-\t-

            """
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Duplicate LLVM run manifest entries"))
        #expect(result.stderr.contains("EmptyMain.range"))
    }

    @Test("Run manifest rejects invalid expected exit")
    func runManifestRejectsInvalidExpectedExit() throws {
        let example = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/EmptyMain.range")
        let manifest = try temporaryManifest(
            contents: "\(example.path)\t999\t-\t-\t-\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Invalid expected exit '999'"))
    }

    @Test("Run manifest rejects missing source files")
    func runManifestRejectsMissingSourceFiles() throws {
        let missing = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/Missing.range")
        let manifest = try temporaryManifest(
            contents: "\(missing.path)\t0\t-\t-\t-\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("references missing source"))
        #expect(result.stderr.contains("Missing.range"))
    }

    @Test("Run manifest checks executable stdout")
    func runManifestChecksExecutableStdout() throws {
        let example = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/PrintString.range")
        let manifest = try temporaryManifest(
            contents: "\(example.path)\t0\t-\t-\tHello from Range\\n\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path], timeout: 30)

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("LLVM run checks succeeded for 1 example(s)."))
        #expect(result.stderr.isEmpty)
    }

    @Test("Bootstrap compiler check scans Range compiler sources")
    func bootstrapCompilerCheckBuildsAndRunsRangeCompilerProgram() throws {
        let result = try runRangeScript(arguments: ["check-bootstrap-compiler"], timeout: 30)

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Bootstrap compiler check succeeded:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/llvm/Compiler"))
        #expect(result.stderr.isEmpty)
    }

    @Test("Native compiler lexer matches Swift bootstrap lexer corpus")
    func nativeCompilerLexerMatchesSwiftBootstrapLexerCorpus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let synthetic = directory.appendingPathComponent("LexerParity.range")
        try """
        @main {
            let escaped: `if`(1)
            let numbers: Pair(1, 2.5)
            let operators: Bool(a == b != c <= d >= e && f || g ?? h)
            let punctuation: Bag([a, b], #(value), value.path...)
            return 0
        }
        """.write(to: synthetic, atomically: true, encoding: .utf8)

        let root = try repositoryRoot()
        let sources = [
            root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range"),
            synthetic,
        ]

        for source in sources {
            let nativeTokens = try nativeCompilerLexerTokens(for: source)
            let swiftTokens = try swiftBootstrapLexerTokens(for: source)
            #expect(nativeTokens == swiftTokens, "Lexer mismatch for \(source.lastPathComponent)")
        }
    }

    @Test("Native compiler parses main block")
    func nativeCompilerParsesMainBlock() throws {
        let source = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range")
        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 30
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("parse\\tmainBlock"))
        #expect(result.stdout.contains("stage2\\tmainFunction\\tname=main"))
        #expect(result.stdout.contains("attributeStart=0"))
        #expect(result.stdout.contains("bodyStart="))
        #expect(result.stdout.contains("bodyEnd="))
    }

    @Test("Native compiler lowers main block to stage2 main function")
    func nativeCompilerLowersMainBlockToStage2MainFunction() throws {
        let source = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range")
        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 30
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("stage2\\tmainFunction\\tname=main"))
        #expect(result.stdout.contains("bodyStart="))
        #expect(result.stdout.contains("bodyEnd="))
    }

    @Test("Native compiler emits LLVM for integer main return")
    func nativeCompilerEmitsLLVMForIntegerMainReturn() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("ReturnSeven.range")
        try """
        @main {
            return 7
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 30
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("llvm\\tmain\\treturn=7"))
        #expect(result.stdout.contains("llvmText\\tdefine i32 @main()"))
        #expect(result.stdout.contains("ret i32 7"))
    }

    @Test("Native compiler parses function declarations")
    func nativeCompilerParsesFunctionDeclarations() throws {
        let source = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Parser.range")
        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 30
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("parse\\tnoMainBlock"))
        #expect(result.stdout.contains("parse\\tfunction\\tname=parseRangeSource"))
        #expect(result.stdout.contains("parse\\tfunction\\tname=parseRangeMainBlock"))
        #expect(result.stdout.contains("parse\\tfunction\\tname=parseRangeFunctionDeclarations"))
        #expect(result.stdout.contains("parse\\tfunction\\tname=parseRangeFunctionDeclaration"))
    }

    @Test("Emit example check rejects missing directories")
    func emitExampleCheckRejectsMissingDirectories() throws {
        let missing = try repositoryRoot()
            .appendingPathComponent(
                "RangePlayground/Examples/LLVM/MissingDirectory",
                isDirectory: true
            )

        let result = try runRangeScript(arguments: ["check-llvm-examples", missing.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Missing LLVM examples directory"))
    }

    @Test("Emit example check rejects empty directories")
    func emitExampleCheckRejectsEmptyDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runRangeScript(arguments: ["check-llvm-examples", directory.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("No LLVM examples found"))
    }
}

private func runRangeScript(arguments: [String], timeout: TimeInterval = 10) throws -> ScriptResult {
    let process = Process()
    process.executableURL = try repositoryRoot()
        .appendingPathComponent("scripts/range")
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    let prebuiltRangeCompiler = try repositoryRoot()
        .appendingPathComponent("RangeCompiler/.build/debug/range")
    if FileManager.default.isExecutableFile(atPath: prebuiltRangeCompiler.path) {
        environment["RANGE_BIN"] = prebuiltRangeCompiler.path
    }
    process.environment = environment

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    let timedOut = process.isRunning
    if timedOut {
        process.terminate()
    }
    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    return ScriptResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? "",
        timedOut: timedOut
    )
}

private func temporaryManifest(contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = directory.appendingPathComponent("manifest.tsv")
    try contents.write(to: manifest, atomically: true, encoding: .utf8)
    return manifest
}

private func rangeExampleNames(in directory: URL) throws -> [String] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw RangeScriptTestError.missingDirectory(directory.path)
    }

    var names: [String] = []
    while let url = enumerator.nextObject() as? URL {
        let isRegularFile =
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegularFile, url.pathExtension == "range" else {
            continue
        }
        names.append(url.lastPathComponent)
    }
    return names.sorted()
}

private func runManifestNames(in manifest: URL) throws -> [String] {
    let text = try String(contentsOf: manifest, encoding: .utf8)
    return text.split(separator: "\n")
        .compactMap { line -> String? in
            guard !line.isEmpty, !line.hasPrefix("#") else {
                return nil
            }
            return line.split(separator: "\t", omittingEmptySubsequences: false)
                .first
                .map(String.init)
        }
        .sorted()
}

private func nativeLexerTokens(from stdout: String) -> [LexerTokenSnapshot] {
    stdout
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t")
        .split(separator: "\n")
        .compactMap { line -> LexerTokenSnapshot? in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3, Int(columns[0]) != nil else {
                return nil
            }
            return LexerTokenSnapshot(kind: String(columns[1]), source: String(columns[2]))
        }
}

private func nativeCompilerLexerTokens(for source: URL) throws -> [LexerTokenSnapshot] {
    let compiler = try repositoryRoot()
        .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
    let result = try runRangeScript(
        arguments: ["run", compiler.path, "--", source.path],
        timeout: 30
    )

    if result.timedOut || result.exitCode != 0 || !result.stderr.isEmpty {
        throw RangeScriptTestError.nativeLexerFailed(source.path, result.stderr)
    }

    return nativeLexerTokens(from: result.stdout)
}

private func swiftBootstrapLexerTokens(for source: URL) throws -> [LexerTokenSnapshot] {
    let text = try String(contentsOf: source, encoding: .utf8)
    let result = RangeAuthoredLexer().tokenize(source: text, foreignBodies: [])
    switch result {
    case .success(let tokens):
        return tokens.compactMap { token -> LexerTokenSnapshot? in
            let kind = swiftBootstrapLexerKindName(token.kind)
            guard kind != "eof" else {
                return nil
            }
            return LexerTokenSnapshot(kind: kind, source: token.source)
        }
    case .failure(let error):
        throw RangeScriptTestError.swiftLexerFailed(error.message)
    }
}

private func swiftBootstrapLexerKindName(_ kind: RangeAuthoredTokenKind) -> String {
    switch kind {
    case .hash:
        return "hash"
    case .identifier:
        return "identifier"
    case .foreignBody:
        return "foreignBody"
    case .stringLiteral:
        return "stringLiteral"
    case .integer:
        return "integer"
    case .double:
        return "double"
    case .keyword:
        return "keyword"
    case .macroAttribute:
        return "macroAttribute"
    case .leftBrace:
        return "leftBrace"
    case .rightBrace:
        return "rightBrace"
    case .leftParen:
        return "leftParen"
    case .rightParen:
        return "rightParen"
    case .leftBracket:
        return "leftBracket"
    case .rightBracket:
        return "rightBracket"
    case .asterisk:
        return "asterisk"
    case .dot:
        return "dot"
    case .ellipsis:
        return "ellipsis"
    case .colon:
        return "colon"
    case .arrow:
        return "arrow"
    case .bang:
        return "bang"
    case .equal:
        return "equal"
    case .equalEqual:
        return "equalEqual"
    case .bangEqual:
        return "bangEqual"
    case .minus:
        return "minus"
    case .less:
        return "less"
    case .lessEqual:
        return "lessEqual"
    case .greater:
        return "greater"
    case .greaterEqual:
        return "greaterEqual"
    case .plus:
        return "plus"
    case .slash:
        return "slash"
    case .ampersand:
        return "ampersand"
    case .andAnd:
        return "andAnd"
    case .pipe:
        return "pipe"
    case .orOr:
        return "orOr"
    case .question:
        return "question"
    case .questionQuestion:
        return "questionQuestion"
    case .dollar:
        return "dollar"
    case .percent:
        return "percent"
    case .comma:
        return "comma"
    case .eof:
        return "eof"
    }
}

private func repositoryRoot() throws -> URL {
    var current = URL(fileURLWithPath: #filePath)
    while current.path != "/" {
        let script = current
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("range")
        let rangePackage = current
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: script.path),
            FileManager.default.fileExists(atPath: rangePackage.path)
        {
            return current
        }
        current.deleteLastPathComponent()
    }
    throw RangeScriptTestError.repositoryRootNotFound
}

private struct ScriptResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
}

private struct LexerTokenSnapshot: Equatable {
    var kind: String
    var source: String
}

private enum RangeScriptTestError: Error {
    case missingDirectory(String)
    case repositoryRootNotFound
    case nativeLexerFailed(String, String)
    case swiftLexerFailed(String)
}
