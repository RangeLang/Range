import Foundation
import RangeCompiler
import Testing
@testable import RangeEmission

@Suite("LLVM lowering emission")
struct LLVMLoweringEmitterTests {
    @Test("Scalar Int function lowers to textual LLVM IR")
    func scalarIntFunctionLowersToTextualLLVMIR() throws {
        let callable = try parseCallable(
            """
            function add(lhs: Int, rhs: Int): Int {
                return lhs + rhs
            }
            """
        )

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                program: LoweredProgram(
                    macrosByName: [:],
                    callables: [callable],
                    enumerations: [],
                    declarations: [],
                    extensions: [],
                    mainBlock: MainBlockNode(macros: [], body: []),
                    units: []
                )
            )
        )

        #expect(module.moduleName == "RangeScalar")
        #expect(module.loweredSymbols == [
            LLVMLoweredSymbol(rangeName: "add", llvmName: "RangeLLVM_add")
        ])
        #expect(
            module.ir.contains(
                """
                define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs) {
                entry:
                  %1 = add i64 %lhs, %rhs
                  ret i64 %1
                }
                """
            )
        )
    }

    @Test("LLVM lowerability rejects non scalar functions")
    func llvmLowerabilityRejectsNonScalarFunctions() throws {
        let callable = try parseCallable(
            """
            function greet(name: String): String {
                return name
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable) == false)
        let module = try LLVMLoweringEmitter().emitModule(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [callable],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: MainBlockNode(macros: [], body: []),
                units: []
            )
        )
        #expect(module == nil)
    }

    @Test("Nested Int while loops lower to LLVM basic blocks")
    func nestedIntWhileLoopsLowerToLLVMBasicBlocks() throws {
        let callable = try parseCallable(
            """
            function nestedSum(limit: Int): Int {
                state outer: Int(0)
                state total: Int(0)

                while outer < limit {
                    state inner: Int(0)

                    while inner < limit {
                        state total: total + outer + inner
                        state inner: inner + 1
                    }

                    state outer: outer + 1
                }

                return total
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                program: LoweredProgram(
                    macrosByName: [:],
                    callables: [callable],
                    enumerations: [],
                    declarations: [],
                    extensions: [],
                    mainBlock: MainBlockNode(macros: [], body: []),
                    units: []
                )
            )
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_nestedSum(i64 %limit)"))
        #expect(module.ir.contains("%outer.addr = alloca i64"))
        #expect(module.ir.contains("%inner.addr = alloca i64"))
        #expect(module.ir.contains("while.cond.1:"))
        #expect(module.ir.contains("while.body.1:"))
        #expect(module.ir.contains("while.end.1:"))
        #expect(module.ir.contains("while.cond.2:"))
        #expect(module.ir.contains("while.body.2:"))
        #expect(module.ir.contains("while.end.2:"))
        #expect(module.ir.contains("icmp slt i64"))
        #expect(module.ir.contains("br i1"))
        #expect(module.ir.contains("store i64"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("LLVM IR links and runs through clang harness")
    func llvmIRLinksAndRunsThroughClangHarness() throws {
        let callable = try parseCallable(
            """
            function nestedSum(limit: Int): Int {
                state outer: Int(0)
                state total: Int(0)

                while outer < limit {
                    state inner: Int(0)

                    while inner < limit {
                        state total: total + outer + inner
                        state inner: inner + 1
                    }

                    state outer: outer + 1
                }

                return total
            }
            """
        )
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                program: LoweredProgram(
                    macrosByName: [:],
                    callables: [callable],
                    enumerations: [],
                    declarations: [],
                    extensions: [],
                    mainBlock: MainBlockNode(macros: [], body: []),
                    units: []
                )
            )
        )

        let clang = URL(fileURLWithPath: "/usr/bin/clang")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMRunTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let irURL = root.appendingPathComponent("RangeScalar.ll")
        let harnessURL = root.appendingPathComponent("harness.c")
        let executableURL = root.appendingPathComponent("nested-sum")

        try module.ir.write(to: irURL, atomically: true, encoding: .utf8)
        try """
            #include <stdint.h>
            #include <stdio.h>

            extern int64_t RangeLLVM_nestedSum(int64_t limit);

            int main(void) {
                printf("%lld\\n", (long long)RangeLLVM_nestedSum(10));
                return 0;
            }
            """
            .write(to: harnessURL, atomically: true, encoding: .utf8)

        let compile = try run(
            clang,
            arguments: [
                irURL.path,
                harnessURL.path,
                "-O3",
                "-o",
                executableURL.path,
            ]
        )
        #expect(compile.status == 0)

        let runResult = try run(executableURL, arguments: [])
        #expect(runResult.status == 0)
        #expect(runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "900")
    }

    @Test("Swift workspace emission writes LLVM IR artifact")
    func swiftWorkspaceEmissionWritesLLVMIRArtifact() throws {
        let callable = try parseCallable(
            """
            function multiply(lhs: Int, rhs: Int): Int {
                return lhs * rhs
            }
            """
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMLoweringEmitterTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: MainBlockNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Main.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: [callable],
                        mainBlock: nil
                    )
                ]
            ),
            at: root
        )

        let irURL = root.appendingPathComponent("LLVM/RangeScalar.ll")
        let ir = try String(contentsOf: irURL, encoding: .utf8)
        #expect(ir.contains("define i64 @RangeLLVM_multiply(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("%1 = mul i64 %lhs, %rhs"))
    }

    @Test("Swift workspace emission bridges calls to LLVM object")
    func swiftWorkspaceEmissionBridgesCallsToLLVMObject() throws {
        let source = try parseModule(
            """
            function sum3(x: Int, y: Int, z: Int): Int {
                return x + y + z
            }

            @main {
                sum3(x: 1, y: 2, z: 3)
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: MainBlockNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Main.swift",
                        enumerations: source.enumerations,
                        declarations: source.constructs,
                        extensions: source.extensions,
                        callables: source.callables,
                        mainBlock: source.mainBlock
                    )
                ]
            ),
            at: root
        )

        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )

        #expect(package.contains(".unsafeFlags([\"LLVM/RangeScalar.o\"])"))
        #expect(runtime.contains("@_silgen_name(\"RangeLLVM_sum3\")"))
        #expect(runtime.contains("func RangeLLVM_sum3(_ argument0: Int64, _ argument1: Int64, _ argument2: Int64) -> Int64"))
        #expect(main.contains("Int(RangeLLVM_sum3(Int64(1), Int64(2), Int64(3)))"))
        #expect(!main.contains("func sum3"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("LLVM/RangeScalar.ll").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("LLVM/RangeScalar.o").path))
    }

    private func parseCallable(_ source: String) throws -> CallableDeclaration {
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()

        switch sourceFile {
        case .module(let module):
            return try #require(module.callables.first)
        case .construct, .enumeration, .macro, .extensions, .mainBlock:
            Issue.record("Expected module source file with a callable.")
            throw LLVMLoweringEmitterTestError.expectedCallable
        }
    }

    private func parseModule(_ source: String) throws -> ModuleFileNode {
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()

        switch sourceFile {
        case .module(let module):
            return module
        case .construct, .enumeration, .macro, .extensions, .mainBlock:
            Issue.record("Expected module source file.")
            throw LLVMLoweringEmitterTestError.expectedCallable
        }
    }

    private func run(_ executableURL: URL, arguments: [String]) throws -> (
        status: Int32, stdout: String, stderr: String
    ) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private enum LLVMLoweringEmitterTestError: Error {
    case expectedCallable
}
