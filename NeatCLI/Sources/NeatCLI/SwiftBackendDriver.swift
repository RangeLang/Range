import ArgumentParser
import Foundation
import NeatSyntax

struct SwiftBackendDriver {
    func emitProjectWorkspace(at path: String) throws -> URL {
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        else {
            throw ValidationError("Missing input at \(inputURL.path)")
        }

        if isDirectory.boolValue {
            let projectRoot = inputURL
            let packageFile = projectRoot.appendingPathComponent("Package.neat", isDirectory: false)
            guard FileManager.default.fileExists(atPath: packageFile.path) else {
                throw ValidationError("Missing Package.neat in \(projectRoot.path)")
            }

            _ = try PackageManifestLoader.load(from: packageFile)
            let files = try neatFiles(in: projectRoot, excludingManifestAt: packageFile)
            guard !files.isEmpty else {
                throw ValidationError("No .neat source files found in \(projectRoot.path)")
            }

            try ProjectSourceValidator.validateFiles(files)
            let program = try loadSwiftProgram(fromProjectRoot: projectRoot, files: files)
            let buildRoot = projectRoot.appendingPathComponent(
                ".neat/Build/swift", isDirectory: true)
            if FileManager.default.fileExists(atPath: buildRoot.path) {
                try FileManager.default.removeItem(at: buildRoot)
            }
            try SwiftBackendEmitter().emitWorkspace(program: program, at: buildRoot)
            return buildRoot
        }

        guard inputURL.pathExtension.lowercased() == "neat" else {
            throw ValidationError("Expected a .neat file or project directory.")
        }

        let program = try loadSwiftProgram(fromSingleFile: inputURL)
        let buildRoot = inputURL.deletingLastPathComponent()
            .appendingPathComponent(".neat/Build/swift", isDirectory: true)
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        try SwiftBackendEmitter().emitWorkspace(program: program, at: buildRoot)
        return buildRoot
    }

    func emitSwiftSource(at path: String, to outputPath: String) throws {
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        else {
            throw ValidationError("Missing input at \(inputURL.path)")
        }

        let program: SwiftBackendEmitter.Program
        if isDirectory.boolValue {
            let projectRoot = inputURL
            let packageFile = projectRoot.appendingPathComponent("Package.neat", isDirectory: false)
            guard FileManager.default.fileExists(atPath: packageFile.path) else {
                throw ValidationError("Missing Package.neat in \(projectRoot.path)")
            }
            _ = try PackageManifestLoader.load(from: packageFile)
            let files = try neatFiles(in: projectRoot, excludingManifestAt: packageFile)
            guard !files.isEmpty else {
                throw ValidationError("No .neat source files found in \(projectRoot.path)")
            }
            try ProjectSourceValidator.validateFiles(files)
            program = try loadSwiftProgram(fromProjectRoot: projectRoot, files: files)
        } else {
            guard inputURL.pathExtension.lowercased() == "neat" else {
                throw ValidationError("Expected a .neat file or project directory.")
            }
            program = try loadSwiftProgram(fromSingleFile: inputURL)
        }

        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let swift = try SwiftBackendEmitter().emit(program: program)
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

    private func neatFiles(in root: URL, excludingManifestAt manifestURL: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw ValidationError("Could not inspect project files in \(root.path)")
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                if fileURL.lastPathComponent == ".git"
                    || fileURL.lastPathComponent == ".build"
                    || fileURL.lastPathComponent == ".neat"
                {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension.lowercased() == "neat" else {
                continue
            }
            if fileURL.standardizedFileURL == manifestURL.standardizedFileURL {
                continue
            }
            files.append(fileURL)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func loadSwiftProgram(fromSingleFile fileURL: URL) throws -> SwiftBackendEmitter.Program
    {
        let sourceFile = try ProjectSourceValidator.parseSourceFile(at: fileURL)
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return .init(
                callables: [],
                declarations: [],
                mainBlock: mainBlock,
                units: [
                    .init(
                        swiftFileName: fileURL.deletingPathExtension().lastPathComponent + ".swift",
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

    private func loadSwiftProgram(fromProjectRoot root: URL, files: [URL]) throws
        -> SwiftBackendEmitter.Program
    {
        var callables: [CallableDeclaration] = []
        var declarations: [ConstructDeclaration] = []
        var mainBlock: MainBlockNode?
        var units: [SwiftBackendEmitter.SourceUnit] = []

        for fileURL in files {
            let sourceFile = try ProjectSourceValidator.parseSourceFile(at: fileURL)
            let swiftFileName = fileURL.deletingPathExtension().lastPathComponent + ".swift"
            switch sourceFile {
            case .construct(let declaration):
                if declaration.kind == .declaration || declaration.kind == .entry {
                    declarations.append(declaration)
                }
            case .module(let module):
                callables.append(contentsOf: module.callables)
                units.append(
                    .init(
                        swiftFileName: swiftFileName,
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
