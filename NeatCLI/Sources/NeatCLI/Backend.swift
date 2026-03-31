import Foundation
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
        semanticProgram: SemanticProgram
    ) throws -> EmittedWorkspace

    func emitSourceFile(
        project: LoadedProject,
        semanticProgram: SemanticProgram,
        outputURL: URL
    ) throws -> EmittedSourceFile
}

protocol RunnableWorkspaceBackend: Backend {
    func run(workspace: EmittedWorkspace) throws
}

enum BackendRegistry {
    static func `default`() -> any RunnableWorkspaceBackend {
        SwiftBackend()
    }
}
