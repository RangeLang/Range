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

    @Test("quarantined RangeCore loads minimal macro records")
    func quarantinedRangeCoreLoadsMinimalMacroRecords() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())

        #expect(program.declarationGraph.macrosByName["addition"] != nil)
        #expect(program.declarationGraph.macrosByName["assignment"] != nil)
        #expect(program.declarationGraph.macrosByName["float"] != nil)
        #expect(program.declarationGraph.macrosByName["generic"] != nil)
        #expect(program.declarationGraph.macrosByName["if"] != nil)
        #expect(program.declarationGraph.macrosByName["main"] != nil)
        #expect(program.declarationGraph.macrosByName["name"] != nil)
        #expect(program.declarationGraph.macrosByName["int"] != nil)
        #expect(program.declarationGraph.macrosByName["let"] != nil)
        #expect(program.declarationGraph.macrosByName["llvmField"] != nil)
        #expect(program.declarationGraph.macrosByName["reference"] != nil)
        #expect(program.declarationGraph.macrosByName["return"] != nil)
        #expect(program.declarationGraph.macrosByName["state"] != nil)
        #expect(program.declarationGraph.macrosByName["string"] != nil)
        #expect(program.declarationGraph.macrosByName["while"] != nil)
        #expect(program.declarationGraph.macrosByName["construct"] == nil)
        #expect(program.declarationGraph.macrosByName["function"] == nil)
    }

    @Test("let macro name parameter accepts names")
    func letMacroNameParameterAcceptsNames() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let letMacro = try #require(program.declarationGraph.macrosByName["let"])
        let nameParameter = try #require(
            letMacro.parameters.first(where: { $0.localName == "name" })
        )

        #expect(nameParameter.valueCapability == .name)
        #expect(nameParameter.defaultValue == nil)
    }

    @Test("string macro value parameter accepts literals")
    func stringMacroValueParameterAcceptsLiterals() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let stringMacro = try #require(program.declarationGraph.macrosByName["string"])
        let valueParameter = try #require(
            stringMacro.parameters.first(where: { $0.localName == "value" })
        )

        #expect(valueParameter.valueCapability == .literal)
        #expect(valueParameter.defaultValue == nil)
    }

    @Test("int macro configuration parameters accept generics")
    func intMacroConfigurationParametersAcceptGenerics() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let intMacro = try #require(program.declarationGraph.macrosByName["int"])
        let bitsParameter = try #require(
            intMacro.parameters.first(where: { $0.localName == "bits" })
        )
        let signednessParameter = try #require(
            intMacro.parameters.first(where: { $0.localName == "signedness" })
        )

        #expect(bitsParameter.valueCapability == .generic)
        #expect(signednessParameter.valueCapability == .generic)
        #expect(bitsParameter.defaultValue != nil)
        #expect(signednessParameter.defaultValue != nil)
    }

    @Test("macro declaration name accepts names")
    func macroDeclarationNameAcceptsNames() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroCarrierBareName.range",
                source: """
                    @macro(name: sample, result: @string) {
                        @return(value: @string(""))
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)

        #expect(program.declarationGraph.macrosByName["sample"] != nil)
    }

    @Test("top-level main macro blocks survive quarantine")
    func topLevelMainMacroBlocksSurviveQuarantine() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/MacroCarrierMain.range",
                source: """
                    @main {}
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)

        #expect(program.declarationGraph.mainBlockMacros.map(\.name) == ["main"])
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
