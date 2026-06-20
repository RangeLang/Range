import Foundation
import RangeCompiler

public struct SwiftBackendError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public enum SwiftBackendBuildConfiguration {
    case debug
    case release

    var swiftRunArguments: [String] {
        switch self {
        case .debug:
            return ["swift", "run", "RangeGenerated"]
        case .release:
            return ["swift", "run", "-c", "release", "RangeGenerated"]
        }
    }
}

public struct SwiftBackend {
    private let programBuilder = SwiftBackendProgramBuilder()
    private let adapter = SwiftLoweredProgramAdapter()
    private let emitter = SwiftBackendEmitter()

    public init() {}

    public func emitLLVMIR(
        project: SwiftBackendProject,
        compiledProgram: CompiledProgram
    ) throws -> String {
        let program = try programBuilder.buildLLVM(project: project, compiledProgram: compiledProgram)
        let loweredProgram = adapter.adapt(program: program)
        return try emitter.emitLLVMModule(program: loweredProgram).ir
    }

    public func emitLLVMIRFile(
        project: SwiftBackendProject,
        compiledProgram: CompiledProgram,
        outputURL: URL
    ) throws -> URL {
        let ir = try emitLLVMIR(project: project, compiledProgram: compiledProgram)
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try ir.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    public func emitWorkspace(
        project: SwiftBackendProject,
        compiledProgram: CompiledProgram
    ) throws -> URL {
        let program = try programBuilder.build(project: project, compiledProgram: compiledProgram)
        let buildRoot = project.buildRoot
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        let loweredProgram = adapter.adapt(program: program)
        try emitter.emitWorkspace(program: loweredProgram, at: buildRoot)
        return buildRoot
    }

    public func emitSourceFile(
        project: SwiftBackendProject,
        compiledProgram: CompiledProgram,
        outputURL: URL
    ) throws -> URL {
        let program = try programBuilder.build(
            project: project,
            compiledProgram: compiledProgram
        )
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let loweredProgram = adapter.adapt(program: program)
        let swift = try emitter.emit(program: loweredProgram)
        try swift.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    public func run(
        workspaceRoot: URL,
        configuration: SwiftBackendBuildConfiguration = .debug
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = configuration.swiftRunArguments
        process.currentDirectoryURL = workspaceRoot
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SwiftBackendError(
                "Generated Swift workspace failed with exit code \(process.terminationStatus)."
            )
        }
    }
}
