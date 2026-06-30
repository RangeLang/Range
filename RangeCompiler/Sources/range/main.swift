import Foundation
import RangeCompiler
import RangeEmission

struct RangecError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

struct Rangec {
    let arguments: [String]

    func run() throws {
        guard arguments.count >= 2 else {
            throw usageError()
        }

        switch arguments[1] {
        case "emit-llvm":
            try emitLLVM(Array(arguments.dropFirst(2)))
        default:
            throw usageError()
        }
    }

    private func emitLLVM(_ arguments: [String]) throws {
        var rangeRoot: URL?
        var positional: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--range-root":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw RangecError(message: "Missing value after --range-root.")
                }
                rangeRoot = URL(fileURLWithPath: arguments[valueIndex], isDirectory: true)
                    .standardizedFileURL
                index += 2
            default:
                positional.append(argument)
                index += 1
            }
        }

        guard positional.count == 2 else {
            throw usageError()
        }

        let inputURL = URL(fileURLWithPath: positional[0]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: positional[1]).standardizedFileURL
        let resolvedRangeRoot = try rangeRoot ?? defaultRangeRoot()

        let inputs = try sourceInputs(rangeRoot: resolvedRangeRoot, inputURL: inputURL)
        let program = try CompilerPipeline().build(inputs: inputs)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try CapabilityLLVMEmitter().emitModuleFile(
            compiledProgram: program,
            outputURL: outputURL
        )
    }

    private func usageError() -> RangecError {
        RangecError(
            message: """
                Usage:
                  range emit-llvm [--range-root PATH] INPUT OUTPUT
                """
        )
    }

    private func defaultRangeRoot() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["RANGE_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Range", isDirectory: true)
            .standardizedFileURL
        if isExistingDirectory(sourceRoot) {
            return sourceRoot
        }

        throw RangecError(message: "Missing Range root. Pass --range-root PATH.")
    }

    private func sourceInputs(rangeRoot: URL, inputURL: URL) throws -> [SourceInput] {
        var inputs = try rangeFiles(in: rangeRoot, excludingProjectManifest: false).map {
            try sourceInput(fileURL: $0, role: .core)
        }
        inputs.append(contentsOf: try projectInputs(inputURL: inputURL))
        return inputs
    }

    private func projectInputs(inputURL: URL) throws -> [SourceInput] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        else {
            throw RangecError(message: "Missing input at \(inputURL.path).")
        }

        if isDirectory.boolValue {
            return try rangeFiles(in: inputURL, excludingProjectManifest: true).map {
                try sourceInput(fileURL: $0, role: .project)
            }
        }

        guard inputURL.pathExtension.lowercased() == "range" else {
            throw RangecError(message: "Expected a .range file or directory.")
        }
        return [try sourceInput(fileURL: inputURL, role: .project)]
    }

    private func sourceInput(fileURL: URL, role: SourceInputRole) throws -> SourceInput {
        SourceInput(
            path: fileURL.path,
            source: try String(contentsOf: fileURL, encoding: .utf8),
            role: role
        )
    }

    private func rangeFiles(in root: URL, excludingProjectManifest: Bool) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw RangecError(message: "Could not inspect Range files in \(root.path).")
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if shouldSkipDirectory(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension.lowercased() == "range" else {
                continue
            }
            if excludingProjectManifest, fileURL.lastPathComponent == "Project.range" {
                continue
            }
            files.append(fileURL.standardizedFileURL)
        }

        return files.sorted(by: sourceFilePrecedence)
    }

    private func shouldSkipDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if [".git", ".build", ".range", "Examples"].contains(name) {
            return true
        }
        return name == "Exploration" && url.path.contains("/RangeCompiler/Range/Core/")
    }

    private func sourceFilePrecedence(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsPriority = lhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
        let rhsPriority = rhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.path < rhs.path
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

do {
    try Rangec(arguments: CommandLine.arguments).run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
