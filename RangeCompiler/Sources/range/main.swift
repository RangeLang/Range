import Foundation
import RangeCompiler
import RangeEmission

private struct DriverError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func usage() -> String {
    """
    Usage:
      range emit-llvm --range-root ROOT INPUT OUTPUT
    """
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func rangeFiles(in root: URL) throws -> [URL] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw DriverError(message: "Missing directory: \(root.path)")
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
        throw DriverError(message: "Missing input: \(input.path)")
    }

    if isDirectory.boolValue {
        return try rangeFiles(in: input).map { try sourceInput(for: $0, role: .project) }
    }

    return [try sourceInput(for: input, role: .project)]
}

private func emitLLVM(arguments: [String]) throws {
    guard arguments.count == 4, arguments[0] == "--range-root" else {
        throw DriverError(message: usage())
    }

    let rangeRoot = URL(fileURLWithPath: arguments[1])
    let input = URL(fileURLWithPath: arguments[2])
    let output = URL(fileURLWithPath: arguments[3])

    let inputs = try coreInputs(rangeRoot: rangeRoot) + projectInputs(input: input)
    let program = try CompilerPipeline().buildValidated(inputs: inputs)
    let module = try LLVMModuleEmitter().emit(program: program)

    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try module.write(to: output, atomically: true, encoding: .utf8)
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    guard let command = arguments.first else {
        throw DriverError(message: usage())
    }

    switch command {
    case "emit-llvm":
        try emitLLVM(arguments: Array(arguments.dropFirst()))
    default:
        throw DriverError(message: usage())
    }
} catch {
    fail(error.localizedDescription)
}
