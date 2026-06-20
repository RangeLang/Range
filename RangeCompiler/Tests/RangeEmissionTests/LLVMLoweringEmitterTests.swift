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

    @Test("Top-level main function lowers to native LLVM entrypoint")
    func topLevelMainFunctionLowersToNativeLLVMEntrypoint() throws {
        let callable = try parseCallable(
            """
            function main(): Int {
                return 0
            }
            """
        )

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.loweredSymbols == [
            LLVMLoweredSymbol(rangeName: "main", llvmName: "main")
        ])
        #expect(module.ir.contains("define i64 @main()"))
    }

    @Test("String literal return lowers to LLVM UTF8 storage")
    func stringLiteralReturnLowersToLLVMUTF8Storage() throws {
        let callable = try parseCallable(
            """
            function greeting(): String {
                return "hello"
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.String = type { ptr, i64 }"))
        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [6 x i8] c\"hello\\00\", align 1"))
        #expect(module.ir.contains("define %Range.String @RangeLLVM_greeting()"))
        #expect(module.ir.contains("getelementptr inbounds [6 x i8], ptr @.range.string.0, i64 0, i64 0"))
        #expect(module.ir.contains("insertvalue %Range.String undef, ptr"))
        #expect(module.ir.contains("insertvalue %Range.String"))
        #expect(module.ir.contains("i64 5, 1"))
        #expect(module.ir.contains("ret %Range.String"))
    }

    @Test("String parameters can pass through LLVM functions")
    func stringParametersCanPassThroughLLVMFunctions() throws {
        let callable = try parseCallable(
            """
            function greet(name: String): String {
                return name
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.String = type { ptr, i64 }"))
        #expect(module.ir.contains("define %Range.String @RangeLLVM_greet(%Range.String %name)"))
        #expect(module.ir.contains("ret %Range.String %name"))
    }

    @Test("String literals use UTF8 byte counts")
    func stringLiteralsUseUTF8ByteCounts() throws {
        let callable = try parseCallable(
            """
            function greeting(): String {
                return "hé"
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [4 x i8] c\"h\\C3\\A9\\00\", align 1"))
        #expect(module.ir.contains("i64 3, 1"))
    }

    @Test("Calls between LLVM String functions stay in LLVM")
    func callsBetweenLLVMStringFunctionsStayInLLVM() throws {
        let module = try parseModule(
            """
            function echo(value: String): String {
                return value
            }

            function greeting(): String {
                return echo(value: "hello")
            }
            """
        )

        let signatures = Dictionary(
            uniqueKeysWithValues: module.callables.compactMap { callable in
                LLVMLowerability.scalarSignature(for: callable).map { (callable.name, $0) }
            }
        )

        #expect(
            module.callables.allSatisfy {
                LLVMLowerability.canLower($0, lowerableFunctionSignatures: signatures)
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(callables: module.callables)
        )

        #expect(emission.ir.contains("define %Range.String @RangeLLVM_echo(%Range.String %value)"))
        #expect(emission.ir.contains("define %Range.String @RangeLLVM_greeting()"))
        #expect(emission.ir.contains("call %Range.String @RangeLLVM_echo(%Range.String"))
    }

    @Test("Construct values lower to LLVM aggregate insert and extract")
    func constructValuesLowerToLLVMAggregateInsertAndExtract() throws {
        let module = try parseModule(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            construct Label {
                let text: String
            }

            function sum(point: Point): Int {
                return point.x + point.y
            }

            function text(label: Label): String {
                return label.text
            }

            function make(): Point {
                return Point(x: 2, y: 3)
            }

            function makeSum(): Int {
                return sum(point: Point(x: 2, y: 3))
            }
            """
        )
        let layouts = LLVMLowerability.constructLayouts(from: module.constructs)
        let signatures = Dictionary(
            uniqueKeysWithValues: module.callables.compactMap { callable in
                LLVMLowerability.scalarSignature(
                    for: callable,
                    constructLayouts: layouts
                ).map { (callable.name, $0) }
            }
        )

        #expect(layouts["construct:Point"]?.fields.map(\.name) == ["x", "y"])
        #expect(
            module.callables.allSatisfy {
                LLVMLowerability.canLower(
                    $0,
                    lowerableFunctionSignatures: signatures,
                    constructLayouts: layouts
                )
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: module.callables,
                constructLayouts: layouts
            )
        )

        #expect(emission.ir.contains("%Range.Point = type { i64, i64 }"))
        #expect(emission.ir.contains("%Range.Label = type { %Range.String }"))
        #expect(emission.ir.contains("define i64 @RangeLLVM_sum(%Range.Point %point)"))
        #expect(emission.ir.contains("extractvalue %Range.Point %point, 0"))
        #expect(emission.ir.contains("extractvalue %Range.Point %point, 1"))
        #expect(emission.ir.contains("define %Range.String @RangeLLVM_text(%Range.Label %label)"))
        #expect(emission.ir.contains("extractvalue %Range.Label %label, 0"))
        #expect(emission.ir.contains("define %Range.Point @RangeLLVM_make()"))
        #expect(emission.ir.contains("insertvalue %Range.Point undef, i64 2, 0"))
        #expect(emission.ir.contains("insertvalue %Range.Point"))
        #expect(emission.ir.contains("ret %Range.Point"))
        #expect(emission.ir.contains("call i64 @RangeLLVM_sum(%Range.Point"))
    }

    @Test("Duplicate construct display names get distinct LLVM layout identities")
    func duplicateConstructDisplayNamesGetDistinctLLVMLayoutIdentities() throws {
        let left = try parseConstruct(
            """
            construct Thing {
                let id: Int
            }
            """
        )
        let right = try parseConstruct(
            """
            construct Thing {
                let active: Bool
            }
            """
        )

        let layouts = LLVMLowerability.constructLayouts(from: [left, right])

        #expect(Set(layouts.keys) == ["construct:Thing#1", "construct:Thing#2"])
        #expect(
            LLVMLoweringEmitter.constructTypeName(
                identity: "construct:Thing#1",
                name: "Thing"
            )
                != LLVMLoweringEmitter.constructTypeName(
                    identity: "construct:Thing#2",
                    name: "Thing"
                )
        )
    }

    @Test("Nested construct fields lower through LLVM aggregate identities")
    func nestedConstructFieldsLowerThroughLLVMAggregateIdentities() throws {
        let module = try parseModule(
            """
            construct Name {
                let value: String
            }

            construct User {
                let name: Name
            }

            function name(user: User): Name {
                return user.name
            }

            function value(user: User): String {
                return user.name.value
            }

            function make(): User {
                return User(name: Name(value: "George"))
            }
            """
        )
        let layouts = LLVMLowerability.constructLayouts(from: module.constructs)
        let signatures = Dictionary(
            uniqueKeysWithValues: module.callables.compactMap { callable in
                LLVMLowerability.scalarSignature(
                    for: callable,
                    constructLayouts: layouts
                ).map { (callable.name, $0) }
            }
        )

        #expect(layouts["construct:Name"]?.fields.map(\.name) == ["value"])
        #expect(layouts["construct:User"]?.fields.map(\.name) == ["name"])
        #expect(
            module.callables.allSatisfy {
                LLVMLowerability.canLower(
                    $0,
                    lowerableFunctionSignatures: signatures,
                    constructLayouts: layouts
                )
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: module.callables,
                constructLayouts: layouts
            )
        )

        #expect(emission.ir.contains("%Range.Name = type { %Range.String }"))
        #expect(emission.ir.contains("%Range.User = type { %Range.Name }"))
        #expect(emission.ir.contains("define %Range.Name @RangeLLVM_name(%Range.User %user)"))
        #expect(emission.ir.contains("extractvalue %Range.User %user, 0"))
        #expect(emission.ir.contains("define %Range.String @RangeLLVM_value(%Range.User %user)"))
        #expect(emission.ir.contains("extractvalue %Range.Name"))
        #expect(emission.ir.contains("define %Range.User @RangeLLVM_make()"))
        #expect(emission.ir.contains("insertvalue %Range.Name undef, %Range.String"))
        #expect(emission.ir.contains("insertvalue %Range.User undef, %Range.Name"))
    }

    @Test("Recursive value construct layouts are not LLVM lowerable")
    func recursiveValueConstructLayoutsAreNotLLVMLowerable() throws {
        let module = try parseModule(
            """
            construct Node {
                let next: Node
            }

            function next(node: Node): Node {
                return node.next
            }
            """
        )
        let layouts = LLVMLowerability.constructLayouts(from: module.constructs)

        #expect(layouts["construct:Node"] == nil)
        #expect(
            module.callables.allSatisfy {
                LLVMLowerability.scalarSignature(for: $0, constructLayouts: layouts) == nil
            }
        )
    }

    @Test("String isEmpty member lowers through LLVM count projection")
    func stringIsEmptyMemberLowersThroughLLVMCountProjection() throws {
        let callable = try parseCallable(
            """
            function empty(value: String): Bool {
                return value.isEmpty
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_empty(%Range.String %value)"))
        #expect(module.ir.contains("extractvalue %Range.String %value, 1"))
        #expect(module.ir.contains("icmp eq i64"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("String byteCount member lowers through LLVM count projection")
    func stringByteCountMemberLowersThroughLLVMCountProjection() throws {
        let callable = try parseCallable(
            """
            function size(value: String): Int {
                return value.byteCount
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_size(%Range.String %value)"))
        #expect(module.ir.contains("extractvalue %Range.String %value, 1"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("String literal local isEmpty lowers through LLVM")
    func stringLiteralLocalIsEmptyLowersThroughLLVM() throws {
        let callable = try parseCallable(
            """
            function literalEmpty(): Bool {
                let value: String("")
                return value.isEmpty
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [1 x i8] c\"\\00\", align 1"))
        #expect(module.ir.contains("insertvalue %Range.String"))
        #expect(module.ir.contains("store %Range.String"))
        #expect(module.ir.contains("extractvalue %Range.String"))
        #expect(module.ir.contains("icmp eq i64"))
    }

    @Test("String literal local byteCount uses UTF8 byte count through LLVM")
    func stringLiteralLocalByteCountUsesUTF8ByteCountThroughLLVM() throws {
        let callable = try parseCallable(
            """
            function literalSize(): Int {
                let value: String("hé")
                return value.byteCount
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [4 x i8] c\"h\\C3\\A9\\00\", align 1"))
        #expect(module.ir.contains("i64 3, 1"))
        #expect(module.ir.contains("extractvalue %Range.String"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Int array count and isEmpty lower through LLVM")
    func intArrayCountAndIsEmptyLowerThroughLLVM() throws {
        let module = try parseModule(
            """
            function size(values: Array<Int>): Int {
                return values.count
            }

            function empty(values: Array<Int>): Bool {
                return values.isEmpty
            }
            """
        )
        let signatures = Dictionary(
            uniqueKeysWithValues: module.callables.compactMap { callable in
                LLVMLowerability.scalarSignature(for: callable).map { (callable.name, $0) }
            }
        )

        #expect(
            module.callables.allSatisfy {
                LLVMLowerability.canLower($0, lowerableFunctionSignatures: signatures)
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(callables: module.callables)
        )

        #expect(emission.ir.contains("%Range.IntArray = type { ptr, i64, i64 }"))
        #expect(emission.ir.contains("define i64 @RangeLLVM_size(%Range.IntArray %values)"))
        #expect(emission.ir.contains("define i1 @RangeLLVM_empty(%Range.IntArray %values)"))
        #expect(emission.ir.contains("extractvalue %Range.IntArray %values, 1"))
        #expect(emission.ir.contains("icmp eq i64"))
    }

    @Test("Int array element lowers through LLVM pointer load")
    func intArrayElementLowersThroughLLVMPointerLoad() throws {
        let callable = try parseCallable(
            """
            function first(values: Array<Int>): Int {
                return values.element(index: 0)
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.IntArray = type { ptr, i64, i64 }"))
        #expect(module.ir.contains("declare void @llvm.trap() noreturn nounwind"))
        #expect(module.ir.contains("define i64 @RangeLLVM_first(%Range.IntArray %values)"))
        #expect(module.ir.contains("array.element.bounds.ok."))
        #expect(module.ir.contains("array.element.bounds.trap."))
        #expect(module.ir.contains("icmp sge i64 0, 0"))
        #expect(module.ir.contains("icmp slt i64 0,"))
        #expect(module.ir.contains("and i1"))
        #expect(module.ir.contains("call void @llvm.trap()"))
        #expect(module.ir.contains("extractvalue %Range.IntArray %values, 0"))
        #expect(module.ir.contains("getelementptr inbounds i64, ptr"))
        #expect(module.ir.contains("load i64, ptr"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Owned Int array allocation and append lower through LLVM memory")
    func ownedIntArrayAllocationAndAppendLowerThroughLLVMMemory() throws {
        let callable = try parseCallable(
            """
            function sumAllocated(limit: Int): Int {
                state values: Array<Int>(capacity: limit)
                state index: Int(0)

                while index < limit {
                    values.append(element: index)
                    state index: index + 1
                }

                state total: Int(0)
                state readIndex: Int(0)

                while readIndex < limit {
                    state total: total + values.element(index: readIndex)
                    state readIndex: readIndex + 1
                }

                return total
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("declare ptr @malloc(i64)"))
        #expect(module.ir.contains("declare void @free(ptr)"))
        #expect(module.ir.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.ir.contains("declare void @llvm.trap() noreturn nounwind"))
        #expect(module.ir.contains("%Range.IntArray = type { ptr, i64, i64 }"))
        #expect(module.ir.contains("mul i64 %limit, 8"))
        #expect(module.ir.contains("call ptr @malloc(i64"))
        #expect(module.ir.contains("insertvalue %Range.IntArray undef, ptr"))
        #expect(module.ir.contains("insertvalue %Range.IntArray"))
        #expect(module.ir.contains("i64 0, 1"))
        #expect(module.ir.contains("icmp slt i64"))
        #expect(module.ir.contains("array.grow."))
        #expect(module.ir.contains("select i1"))
        #expect(module.ir.contains("call void @llvm.memcpy.p0.p0.i64"))
        #expect(module.ir.contains("array.element.bounds.ok."))
        #expect(module.ir.contains("array.element.bounds.trap."))
        #expect(module.ir.contains("call void @llvm.trap()"))
        #expect(module.ir.contains("call void @free(ptr"))
        #expect(module.ir.contains("store i64"))
        #expect(module.ir.contains("load i64, ptr"))
        #expect(module.ir.contains("define i64 @RangeLLVM_sumAllocated(i64 %limit)"))
    }

    @Test("Default Int array append grows from empty storage")
    func defaultIntArrayAppendGrowsFromEmptyStorage() throws {
        let callable = try parseCallable(
            """
            function grown(): Int {
                state values: Array<Int>
                values.append(element: 4)
                values.append(element: 8)
                return values.element(index: 1)
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("array.grow."))
        #expect(module.ir.contains("ptr null, 0"))
        #expect(module.ir.contains("i64 0, 2"))
        #expect(module.ir.contains("icmp eq i64"))
        #expect(module.ir.contains("icmp ne i64"))
        #expect(module.ir.contains("array.grow.copy."))
        #expect(module.ir.contains("array.grow.finish."))
        #expect(module.ir.contains("select i1"))
        #expect(module.ir.contains("i64 1"))
        #expect(module.ir.contains("call void @llvm.memcpy.p0.p0.i64"))
        #expect(module.ir.contains("call void @free(ptr"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Int array update lowers with LLVM bounds check")
    func intArrayUpdateLowersWithLLVMBoundsCheck() throws {
        let callable = try parseCallable(
            """
            function replaceFirst(value: Int): Int {
                state values: Array<Int>(capacity: 1)
                values.append(element: 0)
                values.update(element: value, index: 0)
                return values.element(index: 0)
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("array.update.bounds.ok."))
        #expect(module.ir.contains("array.update.bounds.trap."))
        #expect(module.ir.contains("icmp sge i64 0, 0"))
        #expect(module.ir.contains("icmp slt i64 0,"))
        #expect(module.ir.contains("call void @llvm.trap()"))
        #expect(module.ir.contains("store i64 %value, ptr"))
        #expect(module.ir.contains("call void @free(ptr"))
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

    @Test("Explicit Int width lowers to matching LLVM integer type")
    func explicitIntWidthLowersToMatchingLLVMIntegerType() throws {
        let callable = try parseCallable(
            """
            function wrapping(value: Int<8, .unsigned>): Int<8, .unsigned> {
                return value + 1
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i8 @RangeLLVM_wrapping(i8 %value)"))
        #expect(module.ir.contains("trunc i64 1 to i8"))
        #expect(module.ir.contains("add i8 %value"))
        #expect(module.ir.contains("ret i8"))
    }

    @Test("Unsigned Int comparison and division use unsigned LLVM operations")
    func unsignedIntComparisonAndDivisionUseUnsignedLLVMOperations() throws {
        let callable = try parseCallable(
            """
            function unsignedOps(lhs: Int<13, .unsigned>, rhs: Int<13, .unsigned>): Bool {
                return lhs / rhs < rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_unsignedOps(i13 %lhs, i13 %rhs)"))
        #expect(module.ir.contains("udiv i13 %lhs, %rhs"))
        #expect(module.ir.contains("icmp ult i13"))
    }

    @Test("Signed custom-width Int comparison uses signed LLVM predicate")
    func signedCustomWidthIntComparisonUsesSignedLLVMPredicate() throws {
        let callable = try parseCallable(
            """
            function signedLess(lhs: Int<13>, rhs: Int<13>): Bool {
                return lhs < rhs
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_signedLess(i13 %lhs, i13 %rhs)"))
        #expect(module.ir.contains("icmp slt i13 %lhs, %rhs"))
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

    @Test("Int switch lowers to LLVM switch")
    func intSwitchLowersToLLVMSwitch() throws {
        let callable = try parseCallable(
            """
            function classify(value: Int): Int {
                switch value {
                case 0:
                    return 10
                case 1:
                    return 20
                default:
                    return 30
                }
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_classify(i64 %value)"))
        #expect(module.ir.contains("switch i64 %value, label %switch.default."))
        #expect(module.ir.contains("i64 0, label %switch.case."))
        #expect(module.ir.contains("i64 1, label %switch.case."))
        #expect(module.ir.contains("ret i64 10"))
        #expect(module.ir.contains("ret i64 20"))
        #expect(module.ir.contains("ret i64 30"))
    }

    @Test("Bool switch lowers to LLVM switch")
    func boolSwitchLowersToLLVMSwitch() throws {
        let callable = try parseCallable(
            """
            function boolScore(flag: Bool): Int {
                switch flag {
                case true:
                    return 1
                default:
                    return 0
                }
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_boolScore(i1 %flag)"))
        #expect(module.ir.contains("switch i1 %flag, label %switch.default."))
        #expect(module.ir.contains("i1 1, label %switch.case."))
        #expect(module.ir.contains("ret i64 1"))
        #expect(module.ir.contains("ret i64 0"))
    }

    @Test("Non returning scalar switch branches join after LLVM switch")
    func nonReturningScalarSwitchBranchesJoinAfterLLVMSwitch() throws {
        let callable = try parseCallable(
            """
            function mapped(value: Int): Int {
                state result: Int(0)

                switch value {
                case 0:
                    state result: 10
                case 1:
                    state result: 20
                default:
                    state result: 30
                }

                return result
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_mapped(i64 %value)"))
        #expect(module.ir.contains("switch i64 %value, label %switch.default."))
        #expect(module.ir.contains("br label %switch.end."))
        #expect(module.ir.contains("switch.end."))
        #expect(module.ir.contains("load i64, ptr %result.addr"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Scalar switch without default is not lowerable")
    func scalarSwitchWithoutDefaultIsNotLowerable() throws {
        let callable = try parseCallable(
            """
            function classify(value: Int): Int {
                switch value {
                case 0:
                    return 10
                }
            }
            """
        )

        #expect(LLVMLowerability.canLower(callable) == false)
        #expect(
            LLVMLowerability.rejectionReason(
                for: callable,
                lowerableFunctionSignatures: [:]
            ) == "switch has no default"
        )
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

        let program = SwiftLoweredProgramAdapter().adapt(
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
            )
        )

        try SwiftBackendEmitter().emitWorkspace(
            program: program,
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

        let program = SwiftLoweredProgramAdapter().adapt(
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
            )
        )

        try SwiftBackendEmitter().emitWorkspace(
            program: program,
            at: root
        )

        let irURL = root.appendingPathComponent("LLVM/RangeScalar.ll")
        let ir = try String(contentsOf: irURL, encoding: .utf8)
        #expect(ir.contains("define i64 @RangeLLVM_multiply(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("%1 = mul i64 %lhs, %rhs"))
    }

    @Test("Swift workspace emission writes hybrid emission report")
    func swiftWorkspaceEmissionWritesHybridEmissionReport() throws {
        let source = try parseModule(
            """
            function add(lhs: Int, rhs: Int): Int {
                return lhs + rhs
            }

            function greet(name: String): String {
                return name
            }
            """
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMEmissionReportTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: source.enumerations,
                declarations: source.constructs,
                extensions: source.extensions,
                mainBlock: MainBlockNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Main.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: source.callables,
                        mainBlock: source.mainBlock
                    )
                ]
            ),
            at: root
        )

        let report = try String(
            contentsOf: root.appendingPathComponent("EmissionReport.txt"),
            encoding: .utf8
        )

        #expect(report.contains("LLVM lowered (2):"))
        #expect(report.contains("- add"))
        #expect(report.contains("- greet"))
        #expect(report.contains("Swift emitted (0):"))
        #expect(report.contains("- none"))
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
        #expect(main.contains("Float(RangeLLVM_mixed(Double(1.5), Int64(2)))"))
        #expect(ir.contains("define double @RangeLLVM_mixed(double %lhs, i64 %rhs)"))
        #expect(ir.contains("sitofp i64 %rhs to double"))
        #expect(!main.contains("func mixed"))
    }

    @Test("Swift workspace emission bridges LLVM String returns")
    func swiftWorkspaceEmissionBridgesLLVMStringReturns() throws {
        let source = try parseModule(
            """
            function greeting(): String {
                return "hello"
            }

            @main {
                greeting()
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringBridgeTests-\(UUID().uuidString)")
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

        #expect(runtime.contains("struct __RangeLLVMString"))
        #expect(runtime.contains("func RangeLLVM_greeting() -> __RangeLLVMString"))
        #expect(main.contains("__RangeLLVMString.decode(RangeLLVM_greeting())"))
        #expect(ir.contains("define %Range.String @RangeLLVM_greeting()"))
        #expect(!main.contains("func greeting"))
    }

    @Test("Swift workspace emission keeps construct helpers inside LLVM island")
    func swiftWorkspaceEmissionKeepsConstructHelpersInsideLLVMIsland() throws {
        let source = try parseModule(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            function make(): Point {
                return Point(x: 2, y: 3)
            }

            function score(): Int {
                let point: Point(make())
                return point.x + point.y
            }

            @main {
                score()
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMConstructIslandTests-\(UUID().uuidString)")
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

        #expect(runtime.contains("func RangeLLVM_score() -> Int64"))
        #expect(!runtime.contains("func RangeLLVM_make"))
        #expect(main.contains("Int(RangeLLVM_score())"))
        #expect(!main.contains("func make"))
        #expect(!main.contains("func score"))
        #expect(ir.contains("%Range.Point = type { i64, i64 }"))
        #expect(ir.contains("define %Range.Point @RangeLLVM_make()"))
        #expect(ir.contains("define i64 @RangeLLVM_score()"))
        #expect(ir.contains("call %Range.Point @RangeLLVM_make()"))
    }

    @Test("Swift workspace emission bridges LLVM String arguments")
    func swiftWorkspaceEmissionBridgesLLVMStringArguments() throws {
        let source = try parseModule(
            """
            function echo(value: String): String {
                return value
            }

            @main {
                echo(value: "hello")
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringArgumentBridgeTests-\(UUID().uuidString)")
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

        #expect(runtime.contains("static func withString<Result>"))
        #expect(runtime.contains("func RangeLLVM_echo(_ argument0: __RangeLLVMString) -> __RangeLLVMString"))
        #expect(
            main.contains(
                "__RangeLLVMString.decode(__RangeLLVMString.withString(\"hello\") { __rangeLLVMStringArgument0 in RangeLLVM_echo(__rangeLLVMStringArgument0) })"
            )
        )
        #expect(ir.contains("define %Range.String @RangeLLVM_echo(%Range.String %value)"))
        #expect(!main.contains("func echo"))
    }

    @Test("Swift workspace emission bridges LLVM String isEmpty Bool returns")
    func swiftWorkspaceEmissionBridgesLLVMStringIsEmptyBoolReturns() throws {
        let source = try parseModule(
            """
            function empty(value: String): Bool {
                return value.isEmpty
            }

            @main {
                empty(value: "")
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringIsEmptyBridgeTests-\(UUID().uuidString)")
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

        #expect(runtime.contains("func RangeLLVM_empty(_ argument0: __RangeLLVMString) -> Bool"))
        #expect(main.contains("__RangeLLVMString.withString(\"\") { __rangeLLVMStringArgument0 in RangeLLVM_empty(__rangeLLVMStringArgument0) }"))
        #expect(ir.contains("define i1 @RangeLLVM_empty(%Range.String %value)"))
        #expect(ir.contains("extractvalue %Range.String %value, 1"))
        #expect(!main.contains("func empty"))
    }

    @Test("Swift workspace emission bridges LLVM String byteCount Int returns")
    func swiftWorkspaceEmissionBridgesLLVMStringByteCountIntReturns() throws {
        let source = try parseModule(
            """
            function size(value: String): Int {
                return value.byteCount
            }

            @main {
                size(value: "hé")
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringByteCountBridgeTests-\(UUID().uuidString)")
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

        #expect(runtime.contains("func RangeLLVM_size(_ argument0: __RangeLLVMString) -> Int64"))
        #expect(main.contains("Int(__RangeLLVMString.withString(\"hé\") { __rangeLLVMStringArgument0 in RangeLLVM_size(__rangeLLVMStringArgument0) })"))
        #expect(ir.contains("define i64 @RangeLLVM_size(%Range.String %value)"))
        #expect(ir.contains("extractvalue %Range.String %value, 1"))
        #expect(!main.contains("func size"))
    }

    @Test("Swift workspace emission bridges LLVM Int array arguments")
    func swiftWorkspaceEmissionBridgesLLVMIntArrayArguments() throws {
        let source = try parseModule(
            """
            function first(values: Array<Int>): Int {
                return values.element(index: 0)
            }

            @main {
                first(values: [1, 2, 3])
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMIntArrayBridgeTests-\(UUID().uuidString)")
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

        #expect(runtime.contains("struct __RangeLLVMIntArray"))
        #expect(runtime.contains("func RangeLLVM_first(_ argument0: __RangeLLVMIntArray) -> Int64"))
        #expect(main.contains("Int(__RangeLLVMIntArray.withIntArray([1, 2, 3]) { __rangeLLVMIntArrayArgument0 in RangeLLVM_first(__rangeLLVMIntArrayArgument0) })"))
        #expect(ir.contains("define i64 @RangeLLVM_first(%Range.IntArray %values)"))
        #expect(ir.contains("load i64, ptr"))
        #expect(!main.contains("func first"))
    }

    @Test("Swift workspace emission converts LLVM Float return for Swift wrappers")
    func swiftWorkspaceEmissionConvertsLLVMFloatReturnForSwiftWrappers() throws {
        let source = try parseModule(
            """
            function mixed(lhs: Float, rhs: Int): Float {
                return lhs + rhs
            }

            function describe(value: Float): String {
                return "\\(value)"
            }

            @main {
                describe(value: mixed(lhs: 1.5, rhs: 2))
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMFloatWrapperBridgeTests-\(UUID().uuidString)")
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

        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )

        #expect(main.contains("func describe(value: Float) -> String"))
        #expect(main.contains("describe(value: Float(RangeLLVM_mixed(Double(1.5), Int64(2))))"))
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

    @Test("Range for loop lowers through adapter into LLVM while")
    func rangeForLoopLowersThroughAdapterIntoLLVMWhile() throws {
        let source = try parseModule(
            """
            function rangeSum(limit: Int): Int {
                state total: Int(0)

                for index in 0..<limit {
                    state total: total + index
                }

                return total
            }
            """
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMRangeForTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let program = SwiftLoweredProgramAdapter().adapt(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: MainBlockNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Loops.swift",
                        enumerations: source.enumerations,
                        declarations: source.constructs,
                        extensions: source.extensions,
                        callables: source.callables,
                        mainBlock: nil
                    )
                ]
            )
        )

        try SwiftBackendEmitter().emitWorkspace(
            program: program,
            at: root
        )

        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/Loops.swift"),
            encoding: .utf8
        )

        #expect(ir.contains("define i64 @RangeLLVM_rangeSum(i64 %limit)"))
        #expect(ir.contains("%__range_index_index.addr = alloca i64"))
        #expect(ir.contains("while.cond."))
        #expect(ir.contains("icmp slt i64"))
        #expect(ir.contains("add i64"))
        #expect(ir.contains("ret i64"))
        #expect(!swift.contains("func rangeSum"))
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
            "define double @RangeLLVM_llvmNestedFloatLoop(i64 %limit)",
            "define i64 @RangeLLVM_llvmChooseInt(i1 %flag, i64 %lhs, i64 %rhs)",
            "define double @RangeLLVM_llvmChooseFloat(i1 %flag, double %lhs, i64 %rhs)",
            "define i1 @RangeLLVM_llvmIsLess(i64 %lhs, i64 %rhs)",
            "define i1 @RangeLLVM_llvmBoth(i1 %lhs, i1 %rhs)",
            "define i64 @RangeLLVM_llvmChoose(i1 %flag, i64 %value)",
            "define i64 @RangeLLVM_llvmClassify(i64 %value)",
            "define i64 @RangeLLVM_llvmBoolScore(i1 %flag)",
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
        #expect(ir.contains("select i1 %flag, i64 %lhs, i64 %rhs"))
        #expect(ir.contains("select i1 %flag, double %lhs"))
        #expect(ir.contains("switch i64 %value, label %switch.default."))
        #expect(ir.contains("switch i1 %flag, label %switch.default."))
        #expect(ir.contains("define double @RangeLLVM_llvmNestedFloatLoop"))
        #expect(ir.contains("sitofp i64"))

        let expectedFunctionNames = [
            "llvmAdd",
            "llvmArithmetic",
            "llvmFloatBlend",
            "llvmMixedFloat",
            "llvmFloatLess",
            "llvmNestedFloatLoop",
            "llvmChooseInt",
            "llvmChooseFloat",
            "llvmIsLess",
            "llvmBoth",
            "llvmChoose",
            "llvmClassify",
            "llvmBoolScore",
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

    @Test("Core Int carries evaluated @integer scalar metadata")
    func coreIntCarriesEvaluatedIntegerScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let intConstruct = try #require(program.declarationGraph.constructsByName["Int"])
        let integerMacro = try #require(
            intConstruct.macros.first(where: { $0.name == "integer" }))
        #expect(integerMacro.evaluatedStringValue == "i64")
    }

    @Test("Int @integer macro evaluated value carries scalar metadata")
    func integerMacroEvaluatedValueCarriesScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let intConstruct = try #require(program.declarationGraph.constructsByName["Int"])
        let integerMacro = try #require(
            intConstruct.macros.first(where: { $0.name == "integer" }))
        #expect(integerMacro.evaluatedStringValue == "i64")
    }

    @Test("Core Bool carries evaluated @bool scalar metadata")
    func coreBoolCarriesEvaluatedBoolScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let boolConstruct = try #require(program.declarationGraph.constructsByName["Bool"])
        let boolMacro = try #require(
            boolConstruct.macros.first(where: { $0.name == "bool" }))
        #expect(boolMacro.evaluatedStringValue == "i1")

        let declarations = constructDeclarations(in: program.expandedFiles)
        let scalarTypes = LLVMLowerability.scalarTypes(from: declarations)
        #expect(scalarTypes["Bool"] == .bool)
    }

    @Test("LLVM lowerability uses evaluated @integer scalar metadata")
    func llvmLowerabilityUsesEvaluatedIntegerScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let declarations = constructDeclarations(in: program.expandedFiles)
        let scalarTypes = LLVMLowerability.scalarTypes(from: declarations)
        #expect(scalarTypes["Int"] == .int(bits: 64, signed: true))

        let callable = try parseCallable(
            """
            function add(lhs: Int, rhs: Int): Int {
                return lhs + rhs
            }
            """
        )
        let signature = try #require(
            LLVMLowerability.scalarSignature(for: callable, scalarTypes: scalarTypes)
        )
        #expect(signature.returnType == .int(bits: 64, signed: true))

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: [callable],
                scalarTypes: scalarTypes
            )
        )
        #expect(module.ir.contains("define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs)"))
    }

    @Test("Extension member lowers directly through receiver scalar metadata")
    func extensionMemberLowersDirectlyThroughReceiverScalarMetadata() throws {
        let extensionDeclaration = try parseExtension(
            """
            extension Int {
                function +(lhs: Self, rhs: Self): Self {
                    return lhs + rhs
                }
            }
            """
        )
        let callable = try #require(extensionDeclaration.callables.first)
        let scalarTypes: [String: LLVMLowerability.ScalarType] = [
            "Int": .int(bits: 64, signed: true)
        ]

        #expect(LLVMLowerability.canLower(callable, scalarTypes: scalarTypes))

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: [callable],
                scalarTypes: scalarTypes
            )
        )
        #expect(module.loweredSymbols == [
            LLVMLoweredSymbol(rangeName: "Int.+", llvmName: "RangeLLVM_Int__")
        ])
        #expect(module.ir.contains("define i64 @RangeLLVM_Int__(i64 %lhs, i64 %rhs)"))
    }

    @Test("Swift backend public LLVM emission accepts function-only single file")
    func swiftBackendPublicLLVMEmissionAcceptsFunctionOnlySingleFile() throws {
        var inputs = try rangeCoreInputs()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunctionOnly-\(UUID().uuidString).range")
        inputs.append(
            SourceInput(
                path: fileURL.path,
                source: """
                    function add(lhs: Int, rhs: Int): Int {
                        return lhs + rhs
                    }
                    """,
                role: .project
            )
        )
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let ir = try SwiftBackend().emitLLVMIR(
            project: SwiftBackendProject(
                projectFiles: [fileURL],
                isSingleFile: true,
                buildRoot: FileManager.default.temporaryDirectory
                    .appendingPathComponent("RangeLLVM-\(UUID().uuidString)")
            ),
            compiledProgram: program
        )

        #expect(ir.contains("; ModuleID = 'RangeScalar'"))
        #expect(ir.contains("define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs)"))
        #expect(!ir.contains("RangeGenerated"))
    }

    @Test("Swift backend public LLVM emission lowers @main block to main function")
    func swiftBackendPublicLLVMEmissionLowersMainBlockToMainFunction() throws {
        var inputs = try rangeCoreInputs()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainBlock-\(UUID().uuidString).range")
        inputs.append(
            SourceInput(
                path: fileURL.path,
                source: """
                    @main {
                    }
                    """,
                role: .project
            )
        )
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let ir = try SwiftBackend().emitLLVMIR(
            project: SwiftBackendProject(
                projectFiles: [fileURL],
                isSingleFile: true,
                buildRoot: FileManager.default.temporaryDirectory
                    .appendingPathComponent("RangeLLVM-\(UUID().uuidString)")
            ),
            compiledProgram: program
        )

        #expect(ir.contains("define i64 @main()"))
        #expect(ir.contains("ret i64 0"))
    }

    @Test("Concrete @llvm body is collected, written, and run through clang")
    func concreteLLVMBodyEmitsWritesAndRuns() throws {
        // A Range-authored @llvm string can be returned through an ordinary
        // String-producing macro, then written to .ll and run through clang.
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ConcreteLLVM.range",
                source: """
                    macro concreteLLVM(): Construct -> String { target, diagnostics in
                        return @llvm(body: "define i64 @range_concrete_answer() {\nentry:\n  ret i64 42\n}")
                    }

                    @concreteLLVM
                    construct ConcreteAnswer {
                        let value: Int
                    }
                    """,
                role: .project
            )
        )
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let construct = try #require(program.declarationGraph.constructsByName["ConcreteAnswer"])
        let concreteLLVM = try #require(
            construct.macros.first(where: { $0.name == "concreteLLVM" })?
                .evaluatedStringValue
        )
        let ir = concreteLLVM + "\n"

        let clang = URL(fileURLWithPath: "/usr/bin/clang")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeConcreteLLVMTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let irURL = root.appendingPathComponent("concrete.ll")
        let harnessURL = root.appendingPathComponent("harness.c")
        let executableURL = root.appendingPathComponent("concrete")

        try ir.write(to: irURL, atomically: true, encoding: .utf8)
        try """
            #include <stdint.h>
            #include <stdio.h>

            extern int64_t range_concrete_answer(void);

            int main(void) {
                printf("%lld\\n", (long long)range_concrete_answer());
                return 0;
            }
            """
            .write(to: harnessURL, atomically: true, encoding: .utf8)

        let compile = try run(
            clang,
            arguments: [irURL.path, harnessURL.path, "-O3", "-o", executableURL.path]
        )
        #expect(compile.status == 0)

        let runResult = try run(executableURL, arguments: [])
        #expect(runResult.status == 0)
        #expect(runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }

    @Test("Multi-line @llvm template splits into instruction lines on newline")
    func multiLineLLVMTemplateSplitsOnNewline() throws {
        let template = SwiftBackendEmitter.CollectedLLVMConstruct(
            constructName: "Int",
            rawBody: "%r = add i$bits $lhs, $rhs\nret i$bits %r"
        )
        let lines = template.lines(bindings: ["bits": "32", "lhs": "%lhs", "rhs": "%rhs"])
        #expect(lines == ["%r = add i32 %lhs, %rhs", "ret i32 %r"])
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

    private func parseConstruct(_ source: String) throws -> ConstructDeclaration {
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()

        switch sourceFile {
        case .construct(let construct):
            return construct
        case .module(let module):
            return try #require(module.constructs.first)
        case .enumeration, .macro, .extensions, .mainBlock:
            Issue.record("Expected construct source file.")
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

    private func parseExtension(_ source: String) throws -> ExtensionDeclaration {
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()

        switch sourceFile {
        case .extensions(let declarations):
            return try #require(declarations.first)
        case .module(let module):
            return try #require(module.extensions.first)
        case .construct, .enumeration, .macro, .mainBlock:
            Issue.record("Expected extension source file.")
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

    return try files.map { file in
            SourceInput(
                path: file.path,
                source: try String(contentsOf: file, encoding: .utf8),
                role: .core
            )
        }
    }

    private func constructDeclarations(in files: [ParsedSourceFile]) -> [ConstructDeclaration] {
        files.flatMap { parsedFile -> [ConstructDeclaration] in
            switch parsedFile.sourceFile {
            case .module(let module):
                return module.constructs
            case .construct(let construct):
                return [construct]
            case .enumeration, .macro, .extensions, .mainBlock:
                return []
            }
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
