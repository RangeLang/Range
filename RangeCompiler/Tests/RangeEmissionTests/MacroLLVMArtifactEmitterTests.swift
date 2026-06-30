import Foundation
import Testing

import RangeCompiler
@testable import RangeEmission

@Suite("Macro LLVM artifact emission")
struct MacroLLVMArtifactEmitterTests {
    @Test("uses Range-authored @main IR")
    func usesRangeAuthoredMainIR() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let module = try MacroLLVMArtifactEmitter().emitModule(compiledProgram: program)

        #expect(
            module.ir
                == """
                define i32 @main() {
                entry:
                  ret i32 0
                }
                """
        )
    }

    @Test("rejects source without macro-produced LLVM IR")
    func rejectsSourceWithoutMacroProducedLLVMIR() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())

        do {
            _ = try MacroLLVMArtifactEmitter().emitModule(compiledProgram: program)
            Issue.record("Expected missing macro-produced IR to fail.")
        } catch let error as MacroLLVMArtifactEmitterError {
            #expect(error == .missingMacroProducedIR)
        }
    }

    @Test("writes macro-produced LLVM module file")
    func writesMacroProducedLLVMModuleFile() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: "@main {}\n",
                role: .project
            )
        )
        let program = try CompilerPipeline().build(inputs: inputs)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeMacroLLVMArtifact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let outputURL = root.appendingPathComponent("Main.ll")
        _ = try MacroLLVMArtifactEmitter().emitModuleFile(
            compiledProgram: program,
            outputURL: outputURL
        )

        #expect(
            try String(contentsOf: outputURL, encoding: .utf8)
                == """
                define i32 @main() {
                entry:
                  ret i32 0
                }

                """
        )
    }
}

private func rangeCoreInputs() throws -> [SourceInput] {
    let root = try repositoryRoot()
        .appendingPathComponent("RangeCompiler", isDirectory: true)
        .appendingPathComponent("Range", isDirectory: true)
    let files =
        try rangeFiles(
            in: root.appendingPathComponent("Core", isDirectory: true),
            excludingExploration: true
        )
        + rangeFiles(
            in: root.appendingPathComponent("Foundation/Macros", isDirectory: true),
            excludingExploration: true
        )

    return try files.map { file in
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: .core
        )
    }
}

private func rangeFiles(in root: URL, excludingExploration: Bool) throws -> [URL] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw MacroLLVMArtifactEmitterTestError.missingDirectory(root.path)
    }

    var files: [URL] = []
    while let url = enumerator.nextObject() as? URL {
        let isDirectory =
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if excludingExploration,
            isDirectory,
            url.lastPathComponent == "Exploration",
            url.path.contains("/RangeCompiler/Range/Core/")
        {
            enumerator.skipDescendants()
            continue
        }
        guard !isDirectory, url.pathExtension.lowercased() == "range" else {
            continue
        }
        files.append(url)
    }

    return files.sorted(by: rangeCoreFilePrecedence)
}

private func rangeCoreFilePrecedence(_ lhs: URL, _ rhs: URL) -> Bool {
    let lhsPriority = lhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
    let rhsPriority = rhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
    if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
    }
    return lhs.path < rhs.path
}

private func repositoryRoot() throws -> URL {
    var current = URL(fileURLWithPath: #filePath)
    while current.path != "/" {
        let candidateCore =
            current
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        let candidateTests = current.appendingPathComponent("Tests", isDirectory: true)
        var isCoreDirectory: ObjCBool = false
        var isTestsDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: candidateCore.path,
            isDirectory: &isCoreDirectory
        ),
            isCoreDirectory.boolValue,
            FileManager.default.fileExists(
                atPath: candidateTests.path,
                isDirectory: &isTestsDirectory
            ),
            isTestsDirectory.boolValue
        {
            return current
        }
        current.deleteLastPathComponent()
    }
    throw MacroLLVMArtifactEmitterTestError.missingDirectory("repository root")
}

private enum MacroLLVMArtifactEmitterTestError: Error {
    case missingDirectory(String)
}
