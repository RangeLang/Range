import ArgumentParser
import Foundation
import NeatSyntax

struct SwiftBackendDriver {
    func emitProjectWorkspace(
        project: LoadedProject,
        semanticProgram: SemanticProgram
    ) throws -> URL {
        let program = try loadSwiftProgram(project: project, semanticProgram: semanticProgram)
        let buildRoot = project.defaultBuildRoot
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        let loweredProgram = SwiftBackendLowerer().lower(program: program)
        try SwiftBackendEmitter().emitWorkspace(program: loweredProgram, at: buildRoot)
        return buildRoot
    }

    func emitSwiftSource(
        project: LoadedProject,
        semanticProgram: SemanticProgram,
        to outputPath: String
    ) throws {
        let program = try loadSwiftProgram(project: project, semanticProgram: semanticProgram)
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let loweredProgram = SwiftBackendLowerer().lower(program: program)
        let swift = try SwiftBackendEmitter().emit(program: loweredProgram)
        try swift.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    func runGeneratedWorkspace(at buildRoot: URL) throws {
        try runProcess(
            executable: "/usr/bin/env",
            arguments: ["swift", "run", "NeatGenerated"],
            currentDirectory: buildRoot
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

    private func loadSwiftProgram(
        project: LoadedProject,
        semanticProgram: SemanticProgram
    ) throws -> SwiftBackendEmitter.Program {
        if project.isSingleFile {
            return try loadSwiftProgram(
                fromSingleFile: project.projectFiles[0],
                semanticProgram: semanticProgram
            )
        }

        return try loadSwiftProgram(semanticProgram: semanticProgram)
    }

    private func loadSwiftProgram(
        fromSingleFile fileURL: URL,
        semanticProgram: SemanticProgram
    ) throws -> SwiftBackendEmitter.Program {
        guard
            let parsedFile = semanticProgram.projectExpandedFiles.first(where: {
                $0.path == fileURL.path
            })
        else {
            throw ValidationError("Failed to expand \(fileURL.lastPathComponent).")
        }
        let sourceFile = parsedFile.sourceFile
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .init(
                callables: [],
                declarations: [],
                mainBlock: mainBlock,
                units: [
                    .init(
                        swiftFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        declarations: [],
                        callables: [],
                        mainBlock: mainBlock
                    )
                ]
            )
        case .module(let module):
            guard let mainBlock = module.mainBlock else {
                throw ValidationError(
                    "Swift backend requires a file with @main { ... } when compiling a single file."
                )
            }
            return .init(
                callables: module.callables,
                declarations: module.constructs.filter {
                    $0.kind == .declaration || $0.kind == .entry
                },
                mainBlock: mainBlock,
                units: [
                    .init(
                        swiftFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
                        declarations: module.constructs.filter {
                            $0.kind == .declaration || $0.kind == .entry
                        },
                        callables: module.callables,
                        mainBlock: mainBlock
                    )
                ]
            )
        case .construct, .enumeration, .protocolDefinition, .macro:
            throw ValidationError(
                "Swift backend requires a file with @main { ... } when compiling a single file."
            )
        case .extensions:
            throw ValidationError("Extension-only files cannot be compiled to Swift directly.")
        }
    }

    private func loadSwiftProgram(semanticProgram: SemanticProgram) throws
        -> SwiftBackendEmitter.Program
    {
        var callables: [CallableDeclaration] = []
        var declarations: [ConstructDeclaration] = []
        var mainBlock: MainBlockNode?
        var units: [SwiftBackendEmitter.SourceUnit] = []

        for parsedFile in semanticProgram.projectExpandedFiles {
            let fileURL = URL(fileURLWithPath: parsedFile.path)
            let sourceFile = parsedFile.sourceFile
            let swiftFileName = fileURL.deletingPathExtension().lastPathComponent + ".swift"
            switch sourceFile {
            case .construct(let declaration):
                if declaration.kind == .declaration || declaration.kind == .entry {
                    declarations.append(declaration)
                }
                units.append(
                    .init(
                        swiftFileName: swiftFileName,
                        declarations: declaration.kind == .declaration || declaration.kind == .entry
                            ? [declaration] : [],
                        callables: [],
                        mainBlock: nil
                    )
                )
            case .module(let module):
                callables.append(contentsOf: module.callables)
                units.append(
                    .init(
                        swiftFileName: swiftFileName,
                        declarations: module.constructs.filter {
                            $0.kind == .declaration || $0.kind == .entry
                        },
                        callables: module.callables,
                        mainBlock: module.mainBlock
                    )
                )
                declarations.append(
                    contentsOf: module.constructs.filter {
                        $0.kind == .declaration || $0.kind == .entry
                    }
                )
                if let block = module.mainBlock {
                    if mainBlock != nil {
                        throw ValidationError(
                            "Found multiple @main modules while generating Swift.")
                    }
                    mainBlock = block
                }
            case .mainBlock(let block):
                if mainBlock != nil {
                    throw ValidationError("Found multiple @main modules while generating Swift.")
                }
                mainBlock = block
                units.append(
                    .init(
                        swiftFileName: swiftFileName,
                        declarations: [],
                        callables: [],
                        mainBlock: block
                    )
                )
            case .extensions, .enumeration, .protocolDefinition, .macro:
                continue
            }
        }

        guard let mainBlock else {
            throw ValidationError("Missing @main block while generating Swift.")
        }

        return .init(
            callables: callables,
            declarations: declarations,
            mainBlock: mainBlock,
            units: units
        )
    }
}
