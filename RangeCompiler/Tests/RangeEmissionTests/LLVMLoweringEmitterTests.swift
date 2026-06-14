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
            try LLVMLoweringEmitter().emitModule(callables: [callable])
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
        let module = try LLVMLoweringEmitter().emitModule(callables: [])
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
            try LLVMLoweringEmitter().emitModule(callables: [callable])
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

    @Test("Let comparison and if lower to LLVM control flow")
    func letComparisonAndIfLowerToLLVMControlFlow() throws {
        let callable = try parseCallable(
            """
            function choose(lhs: Int, rhs: Int): Int {
                let adjusted: Int(lhs)

                if lhs < rhs {
                    return rhs
                } else {
                    return adjusted
                }
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_choose(i64 %lhs, i64 %rhs)"))
        #expect(module.ir.contains("%adjusted.addr = alloca i64"))
        #expect(module.ir.contains("icmp slt i64 %lhs, %rhs"))
        #expect(module.ir.contains("br i1"))
        #expect(module.ir.contains("if.body."))
        #expect(module.ir.contains("ret i64 %rhs"))
    }

    @Test("Scalar literal operands lower through LLVM")
    func scalarLiteralOperandsLowerThroughLLVM() throws {
        let callable = try compileCallable(
            """
            function adjust(value: Int): Int {
                let incremented: Int(value + 1)

                if incremented < 10 {
                    return incremented * 2
                } else {
                    return 10 - value
                }
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_adjust(i64 %value)"))
        #expect(module.ir.contains("add i64 %value, 1"))
        #expect(module.ir.contains("icmp slt i64"))
        #expect(module.ir.contains("mul i64"))
        #expect(module.ir.contains("sub i64 10, %value"))
    }

    @Test("Float arithmetic lowers to LLVM double operations")
    func floatArithmeticLowersToLLVMDoubleOperations() throws {
        let callable = try parseCallable(
            """
            function blend(lhs: Float, rhs: Float): Float {
                let adjusted: Float(lhs + rhs * 2.0)
                return adjusted / 3.0
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define double @RangeLLVM_blend(double %lhs, double %rhs)"))
        #expect(module.ir.contains("fmul double %rhs, 2.0"))
        #expect(module.ir.contains("fadd double %lhs"))
        #expect(module.ir.contains("%adjusted.addr = alloca double"))
        #expect(module.ir.contains("fdiv double"))
        #expect(module.ir.contains("ret double"))
    }

    @Test("Mixed Int and Float operands lower through LLVM promotion")
    func mixedIntAndFloatOperandsLowerThroughLLVMPromotion() throws {
        let callable = try parseCallable(
            """
            function mixed(lhs: Float, rhs: Int): Float {
                return lhs + rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define double @RangeLLVM_mixed(double %lhs, i64 %rhs)"))
        #expect(module.ir.contains("sitofp i64 %rhs to double"))
        #expect(module.ir.contains("fadd double %lhs"))
        #expect(module.ir.contains("ret double"))
    }

    @Test("Float comparison lowers to LLVM ordered comparison")
    func floatComparisonLowersToLLVMOrderedComparison() throws {
        let callable = try parseCallable(
            """
            function floatLess(lhs: Float, rhs: Int): Bool {
                return lhs < rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_floatLess(double %lhs, i64 %rhs)"))
        #expect(module.ir.contains("sitofp i64 %rhs to double"))
        #expect(module.ir.contains("fcmp olt double %lhs"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Scalar ternary lowers to LLVM select")
    func scalarTernaryLowersToLLVMSelect() throws {
        let callable = try parseCallable(
            """
            function choose(flag: Bool, lhs: Int, rhs: Int): Int {
                return flag ? lhs : rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %lhs, i64 %rhs)"))
        #expect(module.ir.contains("select i1 %flag, i64 %lhs, i64 %rhs"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Mixed scalar ternary promotes Int branch to Float")
    func mixedScalarTernaryPromotesIntBranchToFloat() throws {
        let callable = try parseCallable(
            """
            function chooseFloat(flag: Bool, lhs: Float, rhs: Int): Float {
                return flag ? lhs : rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define double @RangeLLVM_chooseFloat(i1 %flag, double %lhs, i64 %rhs)"))
        #expect(module.ir.contains("sitofp i64 %rhs to double"))
        #expect(module.ir.contains("select i1 %flag, double %lhs, double"))
        #expect(module.ir.contains("ret double"))
    }

    @Test("Local scalar plus-equals lowers to LLVM load add store")
    func localScalarPlusEqualsLowersToLLVMLoadAddStore() throws {
        let callable = CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            name: "addLoop",
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: [
                RangeFunctionParameter(
                    macros: [],
                    name: "limit",
                    typeReference: .named("Int"),
                    slotName: nil
                )
            ],
            returnType: .named("Int"),
            body: [
                .localBinding(
                    LocalBindingDeclaration(
                        kind: .mutable,
                        name: "index",
                        hasExplicitTypeAnnotation: true,
                        type: .named("Int"),
                        expression: .integer(0)
                    )
                ),
                .localBinding(
                    LocalBindingDeclaration(
                        kind: .mutable,
                        name: "total",
                        hasExplicitTypeAnnotation: true,
                        type: .named("Int"),
                        expression: .integer(0)
                    )
                ),
                .whileLoop(
                    condition: .binary(
                        lhs: .identifier("index"),
                        operatorSymbol: .less,
                        rhs: .identifier("limit")
                    ),
                    body: [
                        .compoundAssignment(
                            target: .local("total"),
                            operatorSymbol: .plusEquals,
                            expression: .identifier("index")
                        ),
                        .compoundAssignment(
                            target: .local("index"),
                            operatorSymbol: .plusEquals,
                            expression: .integer(1)
                        ),
                    ]
                ),
                .return(.identifier("total")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_addLoop(i64 %limit)"))
        #expect(module.ir.contains("load i64, ptr %total.addr"))
        #expect(module.ir.contains("add i64"))
        #expect(module.ir.contains("store i64"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Int comparison can return Bool through LLVM")
    func intComparisonCanReturnBoolThroughLLVM() throws {
        let callable = try parseCallable(
            """
            function isLess(lhs: Int, rhs: Int): Bool {
                return lhs < rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(module.ir.contains("%1 = icmp slt i64 %lhs, %rhs"))
        #expect(module.ir.contains("ret i1 %1"))
    }

    @Test("Bool operators can return Bool through LLVM")
    func boolOperatorsCanReturnBoolThroughLLVM() throws {
        let callable = try parseCallable(
            """
            function both(lhs: Bool, rhs: Bool): Bool {
                let combined: Bool(lhs && rhs)
                return !combined
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_both(i1 %lhs, i1 %rhs)"))
        #expect(module.ir.contains("%1 = and i1 %lhs, %rhs"))
        #expect(module.ir.contains("%2 = load i1, ptr %combined.addr"))
        #expect(module.ir.contains("xor i1 %2, true"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Bool parameter can control Int return through LLVM")
    func boolParameterCanControlIntReturnThroughLLVM() throws {
        let callable = try parseCallable(
            """
            function choose(flag: Bool, value: Int): Int {
                if flag {
                    return value
                } else {
                    return 0
                }
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %value)"))
        #expect(module.ir.contains("br i1 %flag"))
        #expect(module.ir.contains("ret i64 %value"))
        #expect(module.ir.contains("ret i64 0"))
    }

    @Test("Bool state mutation in loop lowers to LLVM")
    func boolStateMutationInLoopLowersToLLVM() throws {
        let callable = try parseCallable(
            """
            function reachesThreshold(limit: Int): Bool {
                state index: Int(0)
                state found: Bool(false)

                while index < limit {
                    if index > 10 {
                        state found: true
                    }

                    state index: index + 1
                }

                return found
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_reachesThreshold(i64 %limit)"))
        #expect(module.ir.contains("%found.addr = alloca i1"))
        #expect(module.ir.contains("store i1 0, ptr %found.addr"))
        #expect(module.ir.contains("icmp sgt i64"))
        #expect(module.ir.contains("store i1 1, ptr %found.addr"))
        #expect(module.ir.contains("load i1, ptr %found.addr"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Break in loop branches to LLVM loop end")
    func breakInLoopBranchesToLLVMLoopEnd() throws {
        let callable = try parseCallable(
            """
            function firstOverTen(limit: Int): Bool {
                state index: Int(0)
                state found: Bool(false)

                while index < limit {
                    if index > 10 {
                        state found: true
                        break
                    }

                    state index: index + 1
                }

                return found
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_firstOverTen(i64 %limit)"))
        #expect(module.ir.contains("while.cond.1:"))
        #expect(module.ir.contains("while.end.1:"))
        #expect(module.ir.contains("store i1 1, ptr %found.addr"))
        #expect(module.ir.contains("br label %while.end.1"))
    }

    @Test("Continue in loop branches to LLVM loop condition")
    func continueInLoopBranchesToLLVMLoopCondition() throws {
        let callable = try parseCallable(
            """
            function sumOdd(limit: Int): Int {
                state index: Int(0)
                state total: Int(0)

                while index < limit {
                    state index: index + 1

                    if index % 2 == 0 {
                        continue
                    }

                    state total: total + index
                }

                return total
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_sumOdd(i64 %limit)"))
        #expect(module.ir.contains("while.cond.1:"))
        #expect(module.ir.contains("while.end.1:"))
        #expect(module.ir.contains("srem i64"))
        #expect(module.ir.contains("icmp eq i64"))
        #expect(module.ir.contains("br label %while.cond.1"))
    }

    @Test("Calls between lowerable Int functions stay in LLVM")
    func callsBetweenLowerableIntFunctionsStayInLLVM() throws {
        let module = try parseModule(
            """
            function add(lhs: Int, rhs: Int): Int {
                return lhs + rhs
            }

            function sum3(x: Int, y: Int, z: Int): Int {
                let partial: Int(add(lhs: x, rhs: y))
                return add(lhs: partial, rhs: z)
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMCallPlanTests-\(UUID().uuidString)")
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
                        outputFileName: "Math.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: module.callables,
                        mainBlock: nil
                    )
                ]
            ),
            at: root
        )

        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/Math.swift"),
            encoding: .utf8
        )

        #expect(ir.contains("define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("define i64 @RangeLLVM_sum3(i64 %x, i64 %y, i64 %z)"))
        #expect(ir.contains("call i64 @RangeLLVM_add(i64 %x, i64 %y)"))
        #expect(ir.contains("call i64 @RangeLLVM_add"))
        #expect(!swift.contains("func add"))
        #expect(!swift.contains("func sum3"))
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
            try LLVMLoweringEmitter().emitModule(callables: [callable])
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

    @Test("Swift workspace emission bridges mixed Bool and Int LLVM calls")
    func swiftWorkspaceEmissionBridgesMixedBoolAndIntLLVMCalls() throws {
        let source = try parseModule(
            """
            function isLess(lhs: Int, rhs: Int): Bool {
                return lhs < rhs
            }

            function choose(flag: Bool, value: Int): Int {
                if flag {
                    return value
                } else {
                    return 0
                }
            }

            @main {
                choose(flag: isLess(lhs: 1, rhs: 2), value: 42)
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMMixedBridgeTests-\(UUID().uuidString)")
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

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(
            runtime.contains(
                "func RangeLLVM_isLess(_ argument0: Int64, _ argument1: Int64) -> Bool"
            )
        )
        #expect(
            runtime.contains(
                "func RangeLLVM_choose(_ argument0: Bool, _ argument1: Int64) -> Int64"
            )
        )
        #expect(
            main.contains(
                "Int(RangeLLVM_choose(RangeLLVM_isLess(Int64(1), Int64(2)), Int64(42)))"
            )
        )
        #expect(ir.contains("define i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %value)"))
    }

    @Test("Swift workspace emission bridges Float LLVM calls")
    func swiftWorkspaceEmissionBridgesFloatLLVMCalls() throws {
        let source = try parseModule(
            """
            function mixed(lhs: Float, rhs: Int): Float {
                return lhs + rhs
            }

            @main {
                mixed(lhs: 1.5, rhs: 2)
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMFloatBridgeTests-\(UUID().uuidString)")
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

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("func RangeLLVM_mixed(_ argument0: Double, _ argument1: Int64) -> Double"))
        #expect(main.contains("RangeLLVM_mixed(Double(1.5), Int64(2))"))
        #expect(ir.contains("define double @RangeLLVM_mixed(double %lhs, i64 %rhs)"))
        #expect(ir.contains("sitofp i64 %rhs to double"))
        #expect(!main.contains("func mixed"))
    }

    @Test("Mixed scalar calls between LLVM functions stay in LLVM")
    func mixedScalarCallsBetweenLLVMFunctionsStayInLLVM() throws {
        let module = try parseModule(
            """
            function isLess(lhs: Int, rhs: Int): Bool {
                return lhs < rhs
            }

            function invert(value: Bool): Bool {
                return !value
            }

            function choose(flag: Bool, value: Int): Int {
                if flag {
                    return value
                } else {
                    return 0
                }
            }

            function chooseLower(lhs: Int, rhs: Int): Int {
                if isLess(lhs: lhs, rhs: rhs) {
                    return choose(flag: invert(value: false), value: lhs)
                } else {
                    return choose(flag: false, value: rhs)
                }
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMMixedCallChainTests-\(UUID().uuidString)")
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
                        outputFileName: "Math.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: module.callables,
                        mainBlock: nil
                    )
                ]
            ),
            at: root
        )

        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/Math.swift"),
            encoding: .utf8
        )

        #expect(ir.contains("define i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("define i1 @RangeLLVM_invert(i1 %value)"))
        #expect(ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %value)"))
        #expect(ir.contains("define i64 @RangeLLVM_chooseLower(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("call i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("br i1 %"))
        #expect(ir.contains("call i1 @RangeLLVM_invert(i1 0)"))
        #expect(ir.contains("call i64 @RangeLLVM_choose(i1"))
        #expect(!swift.contains("func isLess"))
        #expect(!swift.contains("func invert"))
        #expect(!swift.contains("func choose("))
        #expect(!swift.contains("func chooseLower"))
    }

    @Test("LLVM fixture folder emits documented scalar support")
    func llvmFixtureFolderEmitsDocumentedScalarSupport() throws {
        let fixtureFiles = try llvmFixtureFiles()
        var inputs = try rangeCoreInputs()
        inputs.append(
            contentsOf: try fixtureFiles.map {
                SourceInput(
                    path: $0.path,
                    source: try String(contentsOf: $0, encoding: .utf8),
                    role: .project
                )
            }
        )
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let units = program.projectExpandedFiles.compactMap { parsedFile -> LoweredSourceUnit? in
            guard case .module(let module) = parsedFile.sourceFile else {
                return nil
            }
            let fileName =
                URL(fileURLWithPath: parsedFile.path).deletingPathExtension().lastPathComponent
                + ".swift"
            return LoweredSourceUnit(
                outputFileName: fileName,
                enumerations: module.enumerations,
                declarations: module.constructs,
                extensions: module.extensions,
                callables: module.callables,
                mainBlock: module.mainBlock
            )
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMFixtureFolderTests-\(UUID().uuidString)")
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
                units: units
            ),
            at: root
        )

        let irURL = root.appendingPathComponent("LLVM/RangeScalar.ll")
        let ir = try String(contentsOf: irURL, encoding: .utf8)
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        let emittedSwift = try FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Runtime.swift" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")

        let expectedDefinitions = [
            "define i64 @RangeLLVM_llvmAdd(i64 %lhs, i64 %rhs)",
            "define i64 @RangeLLVM_llvmArithmetic(i64 %value)",
            "define double @RangeLLVM_llvmFloatBlend(double %lhs, double %rhs)",
            "define double @RangeLLVM_llvmMixedFloat(double %lhs, i64 %rhs)",
            "define i1 @RangeLLVM_llvmFloatLess(double %lhs, i64 %rhs)",
            "define i1 @RangeLLVM_llvmIsLess(i64 %lhs, i64 %rhs)",
            "define i1 @RangeLLVM_llvmBoth(i1 %lhs, i1 %rhs)",
            "define i64 @RangeLLVM_llvmChoose(i1 %flag, i64 %value)",
            "define i64 @RangeLLVM_llvmNestedSum(i64 %limit)",
            "define i1 @RangeLLVM_llvmReachesThreshold(i64 %limit)",
            "define i1 @RangeLLVM_llvmFirstOverTen(i64 %limit)",
            "define i64 @RangeLLVM_llvmSumOdd(i64 %limit)",
            "define i1 @RangeLLVM_llvmInvert(i1 %value)",
            "define i64 @RangeLLVM_llvmChooseLower(i64 %lhs, i64 %rhs)",
        ]
        for definition in expectedDefinitions {
            #expect(ir.contains(definition))
        }

        #expect(ir.contains("br label %while.end"))
        #expect(ir.contains("br label %while.cond"))
        #expect(ir.contains("call i1 @RangeLLVM_llvmIsLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("call i64 @RangeLLVM_llvmChoose(i1"))
        #expect(ir.contains("fadd double"))
        #expect(ir.contains("sitofp i64 %rhs to double"))
        #expect(ir.contains("fcmp olt double"))

        let expectedFunctionNames = [
            "llvmAdd",
            "llvmArithmetic",
            "llvmFloatBlend",
            "llvmMixedFloat",
            "llvmFloatLess",
            "llvmIsLess",
            "llvmBoth",
            "llvmChoose",
            "llvmNestedSum",
            "llvmReachesThreshold",
            "llvmFirstOverTen",
            "llvmSumOdd",
            "llvmInvert",
            "llvmChooseLower",
        ]
        for functionName in expectedFunctionNames {
            #expect(!emittedSwift.contains("func \(functionName)"))
        }
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

    private func compileCallable(_ source: String) throws -> CallableDeclaration {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/RangeEmissionTests/LLVMFixture.range",
                source: source,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        for parsedFile in program.projectExpandedFiles {
            if case .module(let module) = parsedFile.sourceFile,
                let callable = module.callables.first
            {
                return callable
            }
        }

        Issue.record("Expected compiled project module with a callable.")
        throw LLVMLoweringEmitterTestError.expectedCallable
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
            + rangeFiles(
                in: root.appendingPathComponent("Lexer", isDirectory: true),
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
            throw LLVMLoweringEmitterTestError.missingDirectory(root.path)
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

        return files.sorted { $0.path < $1.path }
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidateCore =
                current
                .appendingPathComponent("RangeCompiler", isDirectory: true)
                .appendingPathComponent("Range", isDirectory: true)
                .appendingPathComponent("Core", isDirectory: true)
            var isCoreDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: candidateCore.path,
                isDirectory: &isCoreDirectory
            ),
                isCoreDirectory.boolValue
            {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw LLVMLoweringEmitterTestError.missingDirectory("repository root")
    }

    private func llvmFixtureFiles() throws -> [URL] {
        let root = try repositoryRoot()
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("Emission", isDirectory: true)
            .appendingPathComponent("LLVM", isDirectory: true)
        return try rangeFiles(in: root, excludingExploration: false)
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
    case missingDirectory(String)
}
