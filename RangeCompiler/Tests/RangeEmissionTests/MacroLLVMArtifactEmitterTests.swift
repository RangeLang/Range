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
        let mainApplication = try #require(program.declarationGraph.mainBlockMacros.first)
        guard case .object("LLVMModule", let fields)? = mainApplication.evaluatedValue else {
            Issue.record("Expected @main to produce a structured LLVMModule object.")
            return
        }
        #expect(fields["kind"] == .string("llvm-module"))

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

    @Test("emits minimal main body with let and return")
    func emitsMinimalMainBodyWithLetAndReturn() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(name: count, value: @int(value: 5))
                        @return(value: @int(value: 0))
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
                  %count = alloca i64
                  store i64 5, ptr %count
                  ret i32 0
                }
                """
        )
    }

    @Test("emits int value type from Range-authored payload")
    func emitsIntValueTypeFromRangeAuthoredPayload() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(
                            name: count,
                            value: @int(value: 7, bits: 32, signedness: Signedness.unsigned)
                        )
                        @return(value: @int(value: 0))
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
                  %count = alloca i32
                  store i32 7, ptr %count
                  ret i32 0
                }
                """
        )
    }

    @Test("emits minimal main return from reference")
    func emitsMinimalMainReturnFromReference() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(name: count, value: @int(value: 5))
                        @return(value: @reference(name: count))
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
                  %count = alloca i64
                  store i64 5, ptr %count
                  %count.value.0 = load i64, ptr %count
                  %return.1 = trunc i64 %count.value.0 to i32
                  ret i32 %return.1
                }
                """
        )
    }

    @Test("emits minimal main return from addition")
    func emitsMinimalMainReturnFromAddition() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(name: count, value: @int(value: 5))
                        @return(
                            value: @addition(
                                lhs: @reference(name: count),
                                rhs: @int(value: 3)
                            )
                        )
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
                  %count = alloca i64
                  store i64 5, ptr %count
                  %count.value.0 = load i64, ptr %count
                  %add.1 = add i64 %count.value.0, 3
                  %return.2 = trunc i64 %add.1 to i32
                  ret i32 %return.2
                }
                """
        )
    }

    @Test("emits minimal main return from bool reference")
    func emitsMinimalMainReturnFromBoolReference() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(name: flag, value: @bool(value: true))
                        @return(value: @reference(name: flag))
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
                  %flag = alloca i1
                  store i1 1, ptr %flag
                  %flag.value.0 = load i1, ptr %flag
                  %return.1 = zext i1 %flag.value.0 to i32
                  ret i32 %return.1
                }
                """
        )
    }

    @Test("emits minimal main return from float reference")
    func emitsMinimalMainReturnFromFloatReference() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(name: ratio, value: @float(value: 1.5))
                        @return(value: @reference(name: ratio))
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
                  %ratio = alloca double
                  store double 1.5, ptr %ratio
                  %ratio.value.0 = load double, ptr %ratio
                  %return.1 = fptosi double %ratio.value.0 to i32
                  ret i32 %return.1
                }
                """
        )
    }

    @Test("emits float value type from Range-authored precision")
    func emitsFloatValueTypeFromRangeAuthoredPrecision() throws {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: """
                    @main {
                        @let(name: ratio, value: @float(value: 1.5, precision: 32))
                        @return(value: @int(value: 0))
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
                  %ratio = alloca float
                  store float 1.5, ptr %ratio
                  ret i32 0
                }
                """
        )
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
