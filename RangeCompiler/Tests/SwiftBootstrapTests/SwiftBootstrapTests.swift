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

    @Test("checkBootstrapCompiler builds and runs Range compiler program")
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
