import Foundation
import NeatBackendSwift
import NeatSyntax

struct EmittedWorkspace {
    let root: URL
}

struct EmittedSourceFile {
    let outputURL: URL
}

protocol Backend {
    var name: String { get }

    func emitWorkspace(
        project: LoadedProject,
        programModel: ProgramModel
    ) throws -> EmittedWorkspace

    func emitSourceFile(
        project: LoadedProject,
        programModel: ProgramModel,
        outputURL: URL
    ) throws -> EmittedSourceFile
}

protocol RunnableWorkspaceBackend: Backend {
    func run(workspace: EmittedWorkspace) throws
}

enum BackendRegistry {
    static func `default`() -> any RunnableWorkspaceBackend {
        SwiftCLIBackendAdapter()
    }
}

private struct SwiftCLIBackendAdapter: RunnableWorkspaceBackend {
    let backend = SwiftBackend()

    var name: String { "swift" }

    func emitWorkspace(
        project: LoadedProject,
        programModel: ProgramModel
    ) throws -> EmittedWorkspace {
        let root = try backend.emitWorkspace(
            project: .init(
                projectFiles: project.projectFiles,
                isSingleFile: project.isSingleFile,
                buildRoot: project.defaultBuildRoot
            ),
            programModel: programModel
        )
        return EmittedWorkspace(root: root)
    }

    func emitSourceFile(
        project: LoadedProject,
        programModel: ProgramModel,
        outputURL: URL
    ) throws -> EmittedSourceFile {
        let emittedURL = try backend.emitSourceFile(
            project: .init(
                projectFiles: project.projectFiles,
                isSingleFile: project.isSingleFile,
                buildRoot: project.defaultBuildRoot
            ),
            programModel: programModel,
            outputURL: outputURL
        )
        return EmittedSourceFile(outputURL: emittedURL)
    }

    func run(workspace: EmittedWorkspace) throws {
        try backend.run(workspaceRoot: workspace.root)
    }
}
