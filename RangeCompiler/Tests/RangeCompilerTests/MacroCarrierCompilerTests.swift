import Foundation
import Testing

@testable import RangeCompiler

@Suite("Macro carrier compiler")
struct MacroCarrierCompilerTests {
    @Test("Swift-owned roots are rejected")
    func swiftOwnedRootsAreRejected() throws {
        do {
            var parser = try Parser(source: "construct User { }")
            _ = try parser.parseSourceFile()
            Issue.record("Expected bare construct roots to be rejected.")
        } catch {
            #expect(
                String(describing: error).contains(
                    "Range source accepts only @macro declarations and top-level macro blocks."
                )
            )
        }
    }

    @Test("RangeCore declarations build through macro records")
    func rangeCoreDeclarationsBuildThroughMacroRecords() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())

        #expect(program.declarationGraph.constructsByName["Int"] != nil)
        #expect(program.declarationGraph.constructsByName["String"] != nil)
        #expect(program.declarationGraph.constructsByName["Bool"] != nil)
        #expect(program.declarationGraph.constructsByName["Void"] != nil)
        #expect(program.declarationGraph.macrosByName["construct"] != nil)
        #expect(program.declarationGraph.macrosByName["function"] != nil)
    }

    @Test("Top-level macro blocks materialize records")
    func topLevelMacroBlocksMaterializeRecords() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroCarrierCounter.range",
                source: """
                    @construct(name: "Counter") {
                        @let(name: "value") {
                            @value(type: "Int", current: "Int(0)")
                        }
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)

        let counter = try #require(program.declarationGraph.constructsByName["Counter"])
        #expect(counter.macros.first?.name == "construct")
        #expect(program.declarationGraph.values(onConstruct: "Counter").map(\.name) == ["value"])
    }
}

private func rangeCoreInputs() throws -> [SourceInput] {
    let root = try repositoryRoot()
        .appendingPathComponent("RangeCompiler", isDirectory: true)
        .appendingPathComponent("Range", isDirectory: true)
    let files =
        try rangeFiles(in: root.appendingPathComponent("Core", isDirectory: true))
        + (try rangeFiles(in: root.appendingPathComponent("Foundation/Macros", isDirectory: true)))

    return try files.map { file in
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: .core
        )
    }
}

private func rangeFiles(in root: URL) throws -> [URL] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw MacroCarrierFixtureError.missingDirectory(root.path)
    }

    var files: [URL] = []
    while let url = enumerator.nextObject() as? URL {
        let isDirectory =
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
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

    throw MacroCarrierFixtureError.repositoryRootNotFound
}

private enum MacroCarrierFixtureError: Error, CustomStringConvertible {
    case missingDirectory(String)
    case repositoryRootNotFound

    var description: String {
        switch self {
        case .missingDirectory(let path):
            return "Missing fixture directory at \(path)."
        case .repositoryRootNotFound:
            return "Could not find repository root."
        }
    }
}
