import ArgumentParser
import Foundation
import NeatSyntax

struct SwiftBackend: RunnableWorkspaceBackend {
    var name: String { "swift" }
    private let programBuilder = SwiftBackendProgramBuilder()
    private let lowerer = SwiftBackendLowerer()
    private let emitter = SwiftBackendEmitter()

    func emitWorkspace(
        project: LoadedProject,
        semanticProgram: SemanticProgram
    ) throws -> EmittedWorkspace {
        let program = try programBuilder.build(project: project, semanticProgram: semanticProgram)
        let buildRoot = project.defaultBuildRoot
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        let loweredProgram = lowerer.lower(program: program)
        try emitter.emitWorkspace(program: loweredProgram, at: buildRoot)
        return EmittedWorkspace(root: buildRoot)
    }

    func emitSourceFile(
        project: LoadedProject,
        semanticProgram: SemanticProgram,
        outputURL: URL
    ) throws -> EmittedSourceFile {
        let program = try programBuilder.build(project: project, semanticProgram: semanticProgram)
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let loweredProgram = lowerer.lower(program: program)
        let swift = try emitter.emit(program: loweredProgram)
        try swift.write(to: outputURL, atomically: true, encoding: .utf8)
        return EmittedSourceFile(outputURL: outputURL)
    }

    func run(workspace: EmittedWorkspace) throws {
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["swift", "run", "NeatGenerated"],
            currentDirectory: workspace.root
        )
    }

    private func runProcess(executable: String, arguments: [String], currentDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError(
                "Generated Swift workspace failed with exit code \(process.terminationStatus)."
            )
        }
    }
}
