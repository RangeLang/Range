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
        #expect(program.declarationGraph.macrosByName["array"] != nil)
        #expect(program.declarationGraph.macrosByName["assignment"] != nil)
        #expect(program.declarationGraph.macrosByName["case"] != nil)
        #expect(program.declarationGraph.macrosByName["enum"] != nil)
        #expect(program.declarationGraph.macrosByName["field"] != nil)
        #expect(program.declarationGraph.macrosByName["float"] != nil)
        #expect(program.declarationGraph.macrosByName["generic"] != nil)
        #expect(program.declarationGraph.macrosByName["if"] != nil)
        #expect(program.declarationGraph.macrosByName["main"] != nil)
        #expect(program.declarationGraph.macrosByName["name"] != nil)
        #expect(program.declarationGraph.macrosByName["int"] != nil)
        #expect(program.declarationGraph.macrosByName["let"] != nil)
        #expect(program.declarationGraph.macrosByName["local"] != nil)
        #expect(program.declarationGraph.macrosByName["object"] != nil)
        #expect(program.declarationGraph.macrosByName["reference"] != nil)
        #expect(program.declarationGraph.macrosByName["return"] != nil)
        #expect(program.declarationGraph.macrosByName["state"] != nil)
        #expect(program.declarationGraph.macrosByName["string"] != nil)
        #expect(program.declarationGraph.macrosByName["members"] != nil)
        #expect(program.declarationGraph.macrosByName["target"] != nil)
        #expect(program.declarationGraph.macrosByName["void"] != nil)
        #expect(program.declarationGraph.macrosByName["while"] != nil)
        #expect(program.declarationGraph.macrosByName["construct"] == nil)
        #expect(program.declarationGraph.macrosByName["function"] == nil)
    }

    @Test("signedness enum is Range-authored")
    func signednessEnumIsRangeAuthored() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let signedness = try #require(program.declarationGraph.enumsByName["Signedness"])

        #expect(signedness.cases.map(\.name) == ["signed", "unsigned"])
        #expect(signedness.cases.allSatisfy { $0.associatedValues.isEmpty })
    }

    @Test("enum macro records support value-bearing cases")
    func enumMacroRecordsSupportValueBearingCases() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Result.range",
                source: """
                    @enum(name: Result) {
                        @case(name: success, value: @int)
                        @case(name: failure, label: cause, value: @string)
                        @case(name: loading)
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let result = try #require(program.declarationGraph.enumsByName["Result"])

        #expect(result.cases.map(\.name) == ["success", "failure", "loading"])
        #expect(result.cases.count == 3)
        let success = try #require(result.cases.first(where: { $0.name == "success" }))
        let failure = try #require(result.cases.first(where: { $0.name == "failure" }))
        let loading = try #require(result.cases.first(where: { $0.name == "loading" }))
        let successValue = try #require(success.associatedValues.first)
        let failureValue = try #require(failure.associatedValues.first)

        #expect(success.associatedValues.count == 1)
        #expect(successValue.label == nil)
        #expect(successValue.typeReference == .named("@int"))
        #expect(failure.associatedValues.count == 1)
        #expect(failureValue.label == "cause")
        #expect(failureValue.typeReference == .named("@string"))
        #expect(loading.associatedValues.isEmpty)
    }

    @Test("enum macro declares cases member binding")
    func enumMacroDeclaresCasesMemberBinding() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let enumMacro = try #require(program.declarationGraph.macrosByName["enum"])
        let memberBinding = try #require(enumMacro.memberBindings.first)

        #expect(memberBinding.name == "cases")
        #expect(memberBinding.acceptedMacroName == "case")
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
        #expect(stringMacro.expansionType == .named("Object"))
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

    @Test("float macro configuration parameters accept generics")
    func floatMacroConfigurationParametersAcceptGenerics() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let floatMacro = try #require(program.declarationGraph.macrosByName["float"])
        let precisionParameter = try #require(
            floatMacro.parameters.first(where: { $0.localName == "precision" })
        )

        #expect(precisionParameter.valueCapability == .generic)
        #expect(precisionParameter.defaultValue != nil)
    }

    @Test("array macro accepts generic element type and literal elements")
    func arrayMacroAcceptsGenericElementTypeAndLiteralElements() throws {
        let program = try CompilerPipeline().build(inputs: try rangeCoreInputs())
        let arrayMacro = try #require(program.declarationGraph.macrosByName["array"])
        let typeParameter = try #require(
            arrayMacro.parameters.first(where: { $0.localName == "type" })
        )
        let elementsParameter = try #require(
            arrayMacro.parameters.first(where: { $0.localName == "elements" })
        )

        #expect(typeParameter.valueCapability == .generic)
        #expect(typeParameter.defaultValue != nil)
        #expect(elementsParameter.valueCapability == .literal)
        #expect(elementsParameter.defaultValue == nil)
        #expect(arrayMacro.expansionType == .named("Object"))
    }

    @Test("array literal arguments parse as array expressions")
    func arrayLiteralArgumentsParseAsArrayExpressions() throws {
        var parser = try Parser(source: "@array(type: @int, elements: [5, 2, 1, 6])")
        let expression = try parser.parseExpression()
        try parser.consume(.eof)

        guard case .macroInvocation("array", let arguments) = expression else {
            Issue.record("Expected @array invocation.")
            return
        }
        let elementsArgument = try #require(arguments.first(where: { $0.label == "elements" }))
        guard case .array(let elements) = elementsArgument.value else {
            Issue.record("Expected elements argument to parse as an array expression.")
            return
        }

        #expect(elements.count == 4)
        #expect(elements.map { element -> Int? in
            guard case .integer(let value) = element else {
                return nil
            }
            return value
        } == [5, 2, 1, 6])
    }

    @Test("macro applications carry structured evaluated values")
    func macroApplicationsCarryStructuredEvaluatedValues() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/StructuredMacroValue.range",
                source: """
                    @macro(name: sampleObject, result: @object) {
                        @return(value: @object(type: LLVMValue, fields: [
                            @field(name: type, value: "i64"),
                            @field(name: operand, value: 5)
                        ]))
                    }

                    @main
                    @sampleObject {
                    }
                    """,
                role: .project
            )
        )

        let program = try CompilerPipeline().build(inputs: inputs)
        let sampleApplication = try #require(
            program.declarationGraph.mainBlockMacros.first(where: { $0.name == "sampleObject" })
        )

        guard case .object("LLVMValue", let fields)? = sampleApplication.evaluatedValue else {
            Issue.record("Expected structured LLVMValue object.")
            return
        }

        #expect(fields["type"] == .string("i64"))
        #expect(fields["operand"] == .integer(5))
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
