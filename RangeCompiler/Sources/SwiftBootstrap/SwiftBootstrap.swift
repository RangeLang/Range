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
}

private struct ExecutableLayout {
    var buildRoot: URL
    var llvmIR: URL
    var executable: URL
}
