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

    @Test("run links the shared TextBuffer runtime")
    func runLinksSharedTextBufferRuntime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("TextBuffer.range")
        try """
        @main {
            let buffer: TextBuffer(textBufferCreate(capacity: 2))
            if textBufferAppend(buffer: buffer, text: String("range")) != 0 {
                return 1
            }
            if textBufferAppendInt(buffer: buffer, value: 56) != 0 {
                return 2
            }
            if textBufferAppendCharacter(buffer: buffer, source: String("!"), index: 0) != 0 {
                return 5
            }
            let text: String(textBufferMaterialize(buffer: buffer))
            if textBufferDestroy(buffer: buffer) != 0 {
                return 3
            }
            if text == String("range56!") {
                return 0
            }
            return 4
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let exitCode = try SwiftBootstrapCompiler().run(
            rangeRoot: try rangeRoot(),
            input: source,
            arguments: []
        )

        #expect(exitCode == 0)
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
