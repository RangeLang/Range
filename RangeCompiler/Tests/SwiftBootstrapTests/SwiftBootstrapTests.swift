import Foundation
import SwiftBootstrap
import Testing

@Suite("SwiftBootstrap", .serialized)
struct SwiftBootstrapTests {
    @Test("checkLLVMExamples rejects missing directories")
    func checkLLVMExamplesRejectsMissingDirectories() throws {
        let missing = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/MissingDirectory")

        #expect(throws: Error.self) {
            try SwiftBootstrapCompiler().checkLLVMExamples(
                rangeRoot: try rangeRoot(),
                examplesDirectory: missing
            )
        }
    }

    @Test("checkLLVMExamples rejects empty directories")
    func checkLLVMExamplesRejectsEmptyDirectories() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: Error.self) {
            try SwiftBootstrapCompiler().checkLLVMExamples(
                rangeRoot: try rangeRoot(),
                examplesDirectory: directory
            )
        }
    }

    @Test("checkLLVMRuns rejects malformed manifests")
    func checkLLVMRunsRejectsMalformedManifests() throws {
        let manifest = try temporaryManifest(contents: "MissingColumns.range\t0\n")
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        #expect(throws: Error.self) {
            try SwiftBootstrapCompiler().checkLLVMRuns(
                rangeRoot: try rangeRoot(),
                manifest: manifest,
                requireFullCoverage: false
            )
        }
    }

    @Test("checkLLVMRuns verifies stdout")
    func checkLLVMRunsVerifiesStdout() throws {
        let example = try llvmExample("PrintString.range")
        let manifest = try temporaryManifest(
            contents: "\(example.path)\t0\t-\t-\tHello from Range\\n\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let count = try SwiftBootstrapCompiler().checkLLVMRuns(
            rangeRoot: try rangeRoot(),
            manifest: manifest,
            requireFullCoverage: false
        )

        #expect(count == 1)
    }

    @Test("checkLLVMRuns forwards arguments")
    func checkLLVMRunsForwardsArguments() throws {
        let example = try llvmExample("ReturnCommandLineArgumentCount.range")
        let manifest = try temporaryManifest(
            contents: "\(example.path)\t0\t-\talpha beta\t-\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let count = try SwiftBootstrapCompiler().checkLLVMRuns(
            rangeRoot: try rangeRoot(),
            manifest: manifest,
            requireFullCoverage: false
        )

        #expect(count == 1)
    }

    @Test("run returns executable exit code")
    func runReturnsExecutableExitCode() throws {
        let exitCode = try SwiftBootstrapCompiler().run(
            rangeRoot: try rangeRoot(),
            input: try llvmExample("ReturnInteger.range"),
            arguments: []
        )

        #expect(exitCode == 7)
    }

    @Test("run links the shared String runtime")
    func runLinksSharedStringRuntime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("StringPrefix.range")
        try """
        @main {
            let source: String("alpha|beta~gamma")
            let firstSeparator: Int(stringFindFirstOf(source: source, start: 0, characters: String("|~")))
            let recordSeparator: Int(stringFindFrom(source: source, start: 0, needle: String("~")))
            let suffix: String(stringViewFrom(source: source, start: recordSeparator + 1))
            let character: String(stringCharacterAt(source: source, index: firstSeparator + 1))
            let byte: Int(stringByteAt(source: source, index: firstSeparator + 1))
            let nextPipeOrTilde: Int(stringFindByteOf(source: source, start: 0, first: 124, second: 126, third: 0))
            if firstSeparator == 5 && nextPipeOrTilde == 5 && recordSeparator == 10 && character == String("b") && byte == 98 && stringHasPrefix(source: suffix, start: 0, prefix: String("gamma")) {
                return 0
            }
            return 1
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let exitCode = try SwiftBootstrapCompiler().run(
            rangeRoot: try rangeRoot(),
            input: source,
            arguments: []
        )

        #expect(exitCode == 0)
    }

    @Test("checkBootstrapCompiler scans Range compiler sources")
    func checkBootstrapCompilerBuildsAndRunsRangeCompilerProgram() throws {
        let executable = try SwiftBootstrapCompiler().checkBootstrapCompiler(
            rangeRoot: try rangeRoot(),
            compilerDirectory: try compilerProgramDirectory()
        )

        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        #expect(executable.lastPathComponent == "Compiler")
    }

    @Test("native seed driver compiles and runs a single source file")
    func nativeSeedDriverCompilesAndRunsSingleSourceFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("NativeSeven.range")
        try """
        @main {
            return 7
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let root = try repositoryRoot()
        let driver = root.appendingPathComponent("scripts/range-native")
        let compile = try runNativeDriver(
            driver: driver,
            arguments: ["compile-executable", source.path],
            currentDirectory: root
        )
        #expect(compile.exitCode == 0)
        #expect(compile.stderr.isEmpty)
        let executable = compile.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(FileManager.default.isExecutableFile(atPath: executable))

        let run = try runNativeDriver(
            driver: driver,
            arguments: ["run", source.path],
            currentDirectory: root
        )
        #expect(run.exitCode == 7)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
    }

    @Test("native seed driver deterministically compiles a multi-file directory")
    func nativeSeedDriverDeterministicallyCompilesMultiFileDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("NativeProject", isDirectory: true)
        let nested = project.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try """
        @main {
            return helper()
        }
        """.write(to: project.appendingPathComponent("Main.range"), atomically: true, encoding: .utf8)
        try """
        function helper(): Int {
            return 7
        }
        """.write(to: nested.appendingPathComponent("Helper.range"), atomically: true, encoding: .utf8)

        let root = try repositoryRoot()
        let driver = root.appendingPathComponent("scripts/range-native")
        let firstLLVM = directory.appendingPathComponent("First.ll")
        let secondLLVM = directory.appendingPathComponent("Second.ll")
        let first = try runNativeDriver(
            driver: driver,
            arguments: ["emit-llvm", project.path, firstLLVM.path],
            currentDirectory: root
        )
        let second = try runNativeDriver(
            driver: driver,
            arguments: ["emit-llvm", project.path, secondLLVM.path],
            currentDirectory: root
        )
        #expect(first.exitCode == 0)
        #expect(second.exitCode == 0)
        #expect(try Data(contentsOf: firstLLVM) == Data(contentsOf: secondLLVM))

        let run = try runNativeDriver(
            driver: driver,
            arguments: ["run", project.path],
            currentDirectory: root
        )
        #expect(run.exitCode == 7)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
    }
}

private struct NativeDriverResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func runNativeDriver(
    driver: URL,
    arguments: [String],
    currentDirectory: URL
) throws -> NativeDriverResult {
    let process = Process()
    process.executableURL = driver
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return NativeDriverResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func temporaryManifest(contents: String) throws -> URL {
    let directory = try temporaryDirectory()
    let manifest = directory.appendingPathComponent("manifest.tsv")
    try contents.write(to: manifest, atomically: true, encoding: .utf8)
    return manifest
}

private func llvmExample(_ name: String) throws -> URL {
    try repositoryRoot()
        .appendingPathComponent("RangePlayground/Examples/LLVM")
        .appendingPathComponent(name)
}

private func rangeRoot() throws -> URL {
    try repositoryRoot()
        .appendingPathComponent("RangeCompiler/Range", isDirectory: true)
}

private func compilerProgramDirectory() throws -> URL {
    try rangeRoot()
        .appendingPathComponent("Programs/Compiler", isDirectory: true)
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
    throw SwiftBootstrapTestError.repositoryRootNotFound
}

private enum SwiftBootstrapTestError: Error {
    case repositoryRootNotFound
}
