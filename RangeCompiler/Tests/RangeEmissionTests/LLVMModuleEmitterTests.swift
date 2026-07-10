import Foundation
import RangeCompiler
import RangeEmission
import Testing

@Suite("LLVM module emission")
struct LLVMModuleEmitterTests {
    @Test("Empty main emits zero return")
    func emptyMainEmitsZeroReturn() throws {
        let module = try emit(
            """
            @main {
            }
            """
        )

        #expect(module == expectedMain(returning: 0))
    }

    @Test("Bare integer return emits integer return")
    func bareIntegerReturnEmitsIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                return 7
            }
            """
        )

        #expect(module == expectedMain(returning: 7))
    }

    @Test("Int constructor return emits integer return")
    func intConstructorReturnEmitsIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                return Int(9)
            }
            """
        )

        #expect(module == expectedMain(returning: 9))
    }

    @Test("Bool constructor return extends boolean to integer return")
    func boolConstructorReturnExtendsBooleanToIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                return Bool(true)
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = zext i1 1 to i32
                  ret i32 %0
                """
            )
        )
    }

    @Test("Boolean not return emits xor")
    func booleanNotReturnEmitsXor() throws {
        let module = try emit(
            """
            @main {
                return !Bool(false)
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = xor i1 0, true
                  %1 = zext i1 %0 to i32
                  ret i32 %1
                """
            )
        )
    }

    @Test("Boolean and return emits and")
    func booleanAndReturnEmitsAnd() throws {
        let module = try emit(
            """
            @main {
                return Bool(true) && Bool(false)
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = and i1 1, 0
                  %1 = zext i1 %0 to i32
                  ret i32 %1
                """
            )
        )
    }

    @Test("Boolean or return emits or")
    func booleanOrReturnEmitsOr() throws {
        let module = try emit(
            """
            @main {
                return Bool(false) || Bool(true)
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = or i1 0, 1
                  %1 = zext i1 %0 to i32
                  ret i32 %1
                """
            )
        )
    }

    @Test("Boolean logic can initialize state")
    func booleanLogicCanInitializeState() throws {
        let module = try emit(
            """
            @main {
                state value: true && false
                return value ? 1 : 0
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = and i1 1, 0
                  %value = alloca i1
                  store i1 %0, ptr %value
                  %1 = load i1, ptr %value
                  %2 = select i1 %1, i32 1, i32 0
                  ret i32 %2
                """
            )
        )
    }

    @Test("Boolean not can initialize state")
    func booleanNotCanInitializeState() throws {
        let module = try emit(
            """
            @main {
                state value: !false
                return value ? 0 : 1
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = xor i1 0, true
                  %value = alloca i1
                  store i1 %0, ptr %value
                  %1 = load i1, ptr %value
                  %2 = select i1 %1, i32 0, i32 1
                  ret i32 %2
                """
            )
        )
    }

    @Test("Integer comparison return emits icmp")
    func integerComparisonReturnEmitsICmp() throws {
        let module = try emit(
            """
            @main {
                return 5 < 10
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = icmp slt i32 5, 10
                  %1 = zext i1 %0 to i32
                  ret i32 %1
                """
            )
        )
    }

    @Test("Integer local return emits bound integer return")
    func integerLocalReturnEmitsBoundIntegerReturn() throws {
        let module = try emit(
            """
            @main {
                let count: Int(5)
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  ret i32 %0
                """
            )
        )
    }

    @Test("Optional nil local comparison emits validity check")
    func optionalNilLocalComparisonEmitsValidityCheck() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<Int>(nil)
                return maybe == nil
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              %maybe = alloca %Range.Optional.i32
              store %Range.Optional.i32 %0, ptr %maybe
              %1 = load %Range.Optional.i32, ptr %maybe
              %2 = extractvalue %Range.Optional.i32 %1, 0
              %3 = icmp eq i1 %2, 0
              %4 = zext i1 %3 to i32
              ret i32 %4
            }

            """
        )
    }

    @Test("Optional local can be assigned nil")
    func optionalLocalCanBeAssignedNil() throws {
        let module = try emit(
            """
            @main {
                state maybe: Optional<Int>(7)
                maybe: nil
                return maybe == nil
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 1, 0
              %1 = insertvalue %Range.Optional.i32 %0, i32 7, 1
              %maybe = alloca %Range.Optional.i32
              store %Range.Optional.i32 %1, ptr %maybe
              %2 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              store %Range.Optional.i32 %2, ptr %maybe
              %3 = load %Range.Optional.i32, ptr %maybe
              %4 = extractvalue %Range.Optional.i32 %3, 0
              %5 = icmp eq i1 %4, 0
              %6 = zext i1 %5 to i32
              ret i32 %6
            }

            """
        )
    }

    @Test("Optional local can be assigned wrapped value")
    func optionalLocalCanBeAssignedWrappedValue() throws {
        let module = try emit(
            """
            @main {
                state maybe: Optional<Int>(nil)
                maybe: 7
                return maybe ?? 0
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              %maybe = alloca %Range.Optional.i32
              store %Range.Optional.i32 %0, ptr %maybe
              %1 = insertvalue %Range.Optional.i32 undef, i1 1, 0
              %2 = insertvalue %Range.Optional.i32 %1, i32 7, 1
              store %Range.Optional.i32 %2, ptr %maybe
              %3 = load %Range.Optional.i32, ptr %maybe
              %4 = extractvalue %Range.Optional.i32 %3, 0
              %5 = extractvalue %Range.Optional.i32 %3, 1
              %coalesce.result.6 = alloca i32
              br i1 %4, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %5, ptr %coalesce.result.6
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 0, ptr %coalesce.result.6
              br label %coalesce.end.2
            coalesce.end.2:
              %7 = load i32, ptr %coalesce.result.6
              ret i32 %7
            }

            """
        )
    }

    @Test("Optional array local can be assigned empty array")
    func optionalArrayLocalCanBeAssignedEmptyArray() throws {
        let module = try emit(
            """
            @main {
                state maybe: Optional<[Int]>(nil)
                maybe: []
                return maybe == nil ? 1 : 0
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Range_Array_i32 = type { i1, %Range.Array.i32 }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 0, 0
              %maybe = alloca %Range.Optional._Range_Array_i32
              store %Range.Optional._Range_Array_i32 %0, ptr %maybe
              %1 = call ptr @malloc(i64 0)
              %2 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %3 = insertvalue %Range.Array.i32 %2, ptr %1, 1
              %4 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 1, 0
              %5 = insertvalue %Range.Optional._Range_Array_i32 %4, %Range.Array.i32 %3, 1
              store %Range.Optional._Range_Array_i32 %5, ptr %maybe
              %6 = load %Range.Optional._Range_Array_i32, ptr %maybe
              %7 = extractvalue %Range.Optional._Range_Array_i32 %6, 0
              %8 = icmp eq i1 %7, 0
              %9 = select i1 %8, i32 1, i32 0
              ret i32 %9
            }

            """
        )
    }

    @Test("Optional enum local can be assigned wrapped case")
    func optionalEnumLocalCanBeAssignedWrappedCase() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                state maybe: Optional<NumberToken>(nil)
                maybe: .value(value: 7)
                let fallback: NumberToken(.eof)
                let token: NumberToken(maybe ?? fallback)
                switch token {
                case .value(let number):
                    return number
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._NumberToken = type { i1, %NumberToken }

            %NumberToken = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional._NumberToken undef, i1 0, 0
              %maybe = alloca %Range.Optional._NumberToken
              store %Range.Optional._NumberToken %0, ptr %maybe
              %1 = insertvalue %NumberToken undef, i32 0, 0
              %2 = insertvalue %NumberToken %1, i32 7, 1
              %3 = insertvalue %Range.Optional._NumberToken undef, i1 1, 0
              %4 = insertvalue %Range.Optional._NumberToken %3, %NumberToken %2, 1
              store %Range.Optional._NumberToken %4, ptr %maybe
              %5 = insertvalue %NumberToken undef, i32 1, 0
              %fallback = alloca %NumberToken
              store %NumberToken %5, ptr %fallback
              %6 = load %Range.Optional._NumberToken, ptr %maybe
              %7 = load %NumberToken, ptr %fallback
              %8 = extractvalue %Range.Optional._NumberToken %6, 0
              %9 = extractvalue %Range.Optional._NumberToken %6, 1
              %coalesce.result.10 = alloca %NumberToken
              br i1 %8, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store %NumberToken %9, ptr %coalesce.result.10
              br label %coalesce.end.2
            coalesce.fallback.1:
              store %NumberToken %7, ptr %coalesce.result.10
              br label %coalesce.end.2
            coalesce.end.2:
              %11 = load %NumberToken, ptr %coalesce.result.10
              %token = alloca %NumberToken
              store %NumberToken %11, ptr %token
              %12 = load %NumberToken, ptr %token
              br label %switch.check.0.6
            switch.check.0.6:
              %13 = extractvalue %NumberToken %12, 0
              %14 = icmp eq i32 %13, 0
              br i1 %14, label %switch.case.4, label %switch.check.1.7
            switch.case.4:
              %15 = extractvalue %NumberToken %12, 1
              %number.switch.binding.16 = alloca i32
              store i32 %15, ptr %number.switch.binding.16
              %17 = load i32, ptr %number.switch.binding.16
              ret i32 %17
            switch.check.1.7:
              %18 = extractvalue %NumberToken %12, 0
              %19 = icmp eq i32 %18, 1
              br i1 %19, label %switch.case.5, label %switch.end.3
            switch.case.5:
              ret i32 0
            switch.end.3:
              ret i32 0
            }

            """
        )
    }

    @Test("Optional nonnil local condition emits validity bit")
    func optionalNonnilLocalConditionEmitsValidityBit() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<Int>(7)
                if maybe {
                    return 1
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 1, 0
              %1 = insertvalue %Range.Optional.i32 %0, i32 7, 1
              %maybe = alloca %Range.Optional.i32
              store %Range.Optional.i32 %1, ptr %maybe
              %2 = load %Range.Optional.i32, ptr %maybe
              %3 = extractvalue %Range.Optional.i32 %2, 0
              br i1 %3, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 1
            if.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Optional nil coalescing emits fallback branch")
    func optionalNilCoalescingEmitsFallbackBranch() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<Int>(nil)
                return maybe ?? 9
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              %maybe = alloca %Range.Optional.i32
              store %Range.Optional.i32 %0, ptr %maybe
              %1 = load %Range.Optional.i32, ptr %maybe
              %2 = extractvalue %Range.Optional.i32 %1, 0
              %3 = extractvalue %Range.Optional.i32 %1, 1
              %coalesce.result.4 = alloca i32
              br i1 %2, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %3, ptr %coalesce.result.4
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 9, ptr %coalesce.result.4
              br label %coalesce.end.2
            coalesce.end.2:
              %5 = load i32, ptr %coalesce.result.4
              ret i32 %5
            }

            """
        )
    }

    @Test("Optional nonnil coalescing emits payload branch")
    func optionalNonnilCoalescingEmitsPayloadBranch() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<Int>(7)
                return maybe ?? 9
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 1, 0
              %1 = insertvalue %Range.Optional.i32 %0, i32 7, 1
              %maybe = alloca %Range.Optional.i32
              store %Range.Optional.i32 %1, ptr %maybe
              %2 = load %Range.Optional.i32, ptr %maybe
              %3 = extractvalue %Range.Optional.i32 %2, 0
              %4 = extractvalue %Range.Optional.i32 %2, 1
              %coalesce.result.5 = alloca i32
              br i1 %3, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %4, ptr %coalesce.result.5
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 9, ptr %coalesce.result.5
              br label %coalesce.end.2
            coalesce.end.2:
              %6 = load i32, ptr %coalesce.result.5
              ret i32 %6
            }

            """
        )
    }

    @Test("Optional function parameter accepts nil argument")
    func optionalFunctionParameterAcceptsNilArgument() throws {
        let module = try emit(
            """
            function pick(value: Optional<Int>): Int {
                return value ?? 3
            }

            @main {
                return pick(value: nil)
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @pick(%Range.Optional.i32 %value.arg) {
            entry:
              %value = alloca %Range.Optional.i32
              store %Range.Optional.i32 %value.arg, ptr %value
              %0 = load %Range.Optional.i32, ptr %value
              %1 = extractvalue %Range.Optional.i32 %0, 0
              %2 = extractvalue %Range.Optional.i32 %0, 1
              %coalesce.result.3 = alloca i32
              br i1 %1, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %2, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 3, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.end.2:
              %4 = load i32, ptr %coalesce.result.3
              ret i32 %4
            }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              %1 = call i32 @pick(%Range.Optional.i32 %0)
              ret i32 %1
            }

            """
        )
    }

    @Test("Optional function return can be nil coalesced by caller")
    func optionalFunctionReturnCanBeNilCoalescedByCaller() throws {
        let module = try emit(
            """
            function maybe(): Optional<Int> {
                let value: Optional<Int>(7)
                return value
            }

            @main {
                return maybe() ?? 3
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define %Range.Optional.i32 @maybe() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 1, 0
              %1 = insertvalue %Range.Optional.i32 %0, i32 7, 1
              %value = alloca %Range.Optional.i32
              store %Range.Optional.i32 %1, ptr %value
              %2 = load %Range.Optional.i32, ptr %value
              ret %Range.Optional.i32 %2
            }

            define i32 @main() {
            entry:
              %0 = call %Range.Optional.i32 @maybe()
              %1 = extractvalue %Range.Optional.i32 %0, 0
              %2 = extractvalue %Range.Optional.i32 %0, 1
              %coalesce.result.3 = alloca i32
              br i1 %1, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %2, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 3, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.end.2:
              %4 = load i32, ptr %coalesce.result.3
              ret i32 %4
            }

            """
        )
    }

    @Test("Optional function can return nil directly")
    func optionalFunctionCanReturnNilDirectly() throws {
        let module = try emit(
            """
            function maybe(): Optional<Int> {
                return nil
            }

            @main {
                return maybe() ?? 3
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define %Range.Optional.i32 @maybe() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              ret %Range.Optional.i32 %0
            }

            define i32 @main() {
            entry:
              %0 = call %Range.Optional.i32 @maybe()
              %1 = extractvalue %Range.Optional.i32 %0, 0
              %2 = extractvalue %Range.Optional.i32 %0, 1
              %coalesce.result.3 = alloca i32
              br i1 %1, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %2, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 3, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.end.2:
              %4 = load i32, ptr %coalesce.result.3
              ret i32 %4
            }

            """
        )
    }

    @Test("Optional construct function can return nil directly")
    func optionalConstructFunctionCanReturnNilDirectly() throws {
        let module = try emit(
            """
            construct Box {
                let value: Int
            }

            function maybe(): Optional<Box> {
                return nil
            }

            @main {
                return maybe() == nil
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Box = type { i1, %Box }

            %Box = type { i32 }

            define %Range.Optional._Box @maybe() {
            entry:
              %0 = insertvalue %Range.Optional._Box undef, i1 0, 0
              ret %Range.Optional._Box %0
            }

            define i32 @main() {
            entry:
              %0 = call %Range.Optional._Box @maybe()
              %1 = extractvalue %Range.Optional._Box %0, 0
              %2 = icmp eq i1 %1, 0
              %3 = zext i1 %2 to i32
              ret i32 %3
            }

            """
        )
    }

    @Test("Optional construct coalescing emits aggregate branch")
    func optionalConstructCoalescingEmitsAggregateBranch() throws {
        let module = try emit(
            """
            construct Box {
                let value: Int
            }

            @main {
                let maybe: Optional<Box>(nil)
                let chosen: Box(maybe ?? Box(value: 5))
                return chosen.value
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Box = type { i1, %Box }

            %Box = type { i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional._Box undef, i1 0, 0
              %maybe = alloca %Range.Optional._Box
              store %Range.Optional._Box %0, ptr %maybe
              %1 = load %Range.Optional._Box, ptr %maybe
              %2 = insertvalue %Box undef, i32 5, 0
              %3 = extractvalue %Range.Optional._Box %1, 0
              %4 = extractvalue %Range.Optional._Box %1, 1
              %coalesce.result.5 = alloca %Box
              br i1 %3, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store %Box %4, ptr %coalesce.result.5
              br label %coalesce.end.2
            coalesce.fallback.1:
              store %Box %2, ptr %coalesce.result.5
              br label %coalesce.end.2
            coalesce.end.2:
              %6 = load %Box, ptr %coalesce.result.5
              %chosen = alloca %Box
              store %Box %6, ptr %chosen
              %7 = load %Box, ptr %chosen
              %8 = extractvalue %Box %7, 0
              ret i32 %8
            }

            """
        )
    }

    @Test("Optional enum coalescing emits aggregate branch")
    func optionalEnumCoalescingEmitsAggregateBranch() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let maybe: Optional<NumberToken>(nil)
                let fallback: NumberToken(.value(value: 5))
                let token: NumberToken(maybe ?? fallback)
                switch token {
                case .value(let number):
                    return number
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._NumberToken = type { i1, %NumberToken }

            %NumberToken = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional._NumberToken undef, i1 0, 0
              %maybe = alloca %Range.Optional._NumberToken
              store %Range.Optional._NumberToken %0, ptr %maybe
              %1 = insertvalue %NumberToken undef, i32 0, 0
              %2 = insertvalue %NumberToken %1, i32 5, 1
              %fallback = alloca %NumberToken
              store %NumberToken %2, ptr %fallback
              %3 = load %Range.Optional._NumberToken, ptr %maybe
              %4 = load %NumberToken, ptr %fallback
              %5 = extractvalue %Range.Optional._NumberToken %3, 0
              %6 = extractvalue %Range.Optional._NumberToken %3, 1
              %coalesce.result.7 = alloca %NumberToken
              br i1 %5, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store %NumberToken %6, ptr %coalesce.result.7
              br label %coalesce.end.2
            coalesce.fallback.1:
              store %NumberToken %4, ptr %coalesce.result.7
              br label %coalesce.end.2
            coalesce.end.2:
              %8 = load %NumberToken, ptr %coalesce.result.7
              %token = alloca %NumberToken
              store %NumberToken %8, ptr %token
              %9 = load %NumberToken, ptr %token
              br label %switch.check.0.6
            switch.check.0.6:
              %10 = extractvalue %NumberToken %9, 0
              %11 = icmp eq i32 %10, 0
              br i1 %11, label %switch.case.4, label %switch.check.1.7
            switch.case.4:
              %12 = extractvalue %NumberToken %9, 1
              %number.switch.binding.13 = alloca i32
              store i32 %12, ptr %number.switch.binding.13
              %14 = load i32, ptr %number.switch.binding.13
              ret i32 %14
            switch.check.1.7:
              %15 = extractvalue %NumberToken %9, 0
              %16 = icmp eq i32 %15, 1
              br i1 %16, label %switch.case.5, label %switch.end.3
            switch.case.5:
              ret i32 0
            switch.end.3:
              ret i32 0
            }

            """
        )
    }

    @Test("Optional array coalescing emits aggregate branch")
    func optionalArrayCoalescingEmitsAggregateBranch() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<[Int]>(nil)
                let fallback: [Int]([4, 8, 12])
                let chosen: [Int](maybe ?? fallback)
                return chosen[1]
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Range_Array_i32 = type { i1, %Range.Array.i32 }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 0, 0
              %maybe = alloca %Range.Optional._Range_Array_i32
              store %Range.Optional._Range_Array_i32 %0, ptr %maybe
              %1 = call ptr @malloc(i64 12)
              %2 = getelementptr inbounds i32, ptr %1, i32 0
              store i32 4, ptr %2
              %3 = getelementptr inbounds i32, ptr %1, i32 1
              store i32 8, ptr %3
              %4 = getelementptr inbounds i32, ptr %1, i32 2
              store i32 12, ptr %4
              %5 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %6 = insertvalue %Range.Array.i32 %5, ptr %1, 1
              %fallback = alloca %Range.Array.i32
              store %Range.Array.i32 %6, ptr %fallback
              %7 = load %Range.Optional._Range_Array_i32, ptr %maybe
              %8 = load %Range.Array.i32, ptr %fallback
              %9 = extractvalue %Range.Optional._Range_Array_i32 %7, 0
              %10 = extractvalue %Range.Optional._Range_Array_i32 %7, 1
              %coalesce.result.11 = alloca %Range.Array.i32
              br i1 %9, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store %Range.Array.i32 %10, ptr %coalesce.result.11
              br label %coalesce.end.2
            coalesce.fallback.1:
              store %Range.Array.i32 %8, ptr %coalesce.result.11
              br label %coalesce.end.2
            coalesce.end.2:
              %12 = load %Range.Array.i32, ptr %coalesce.result.11
              %chosen = alloca %Range.Array.i32
              store %Range.Array.i32 %12, ptr %chosen
              %13 = load %Range.Array.i32, ptr %chosen
              %14 = extractvalue %Range.Array.i32 %13, 1
              %15 = getelementptr inbounds i32, ptr %14, i32 1
              %16 = load i32, ptr %15
              ret i32 %16
            }

            """
        )
    }

    @Test("Optional array can coalesce to empty fallback")
    func optionalArrayCanCoalesceToEmptyFallback() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<[Int]>(nil)
                let chosen: [Int](maybe ?? [])
                return chosen.count
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Range_Array_i32 = type { i1, %Range.Array.i32 }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 0, 0
              %maybe = alloca %Range.Optional._Range_Array_i32
              store %Range.Optional._Range_Array_i32 %0, ptr %maybe
              %1 = load %Range.Optional._Range_Array_i32, ptr %maybe
              %2 = call ptr @malloc(i64 0)
              %3 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %4 = insertvalue %Range.Array.i32 %3, ptr %2, 1
              %5 = extractvalue %Range.Optional._Range_Array_i32 %1, 0
              %6 = extractvalue %Range.Optional._Range_Array_i32 %1, 1
              %coalesce.result.7 = alloca %Range.Array.i32
              br i1 %5, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store %Range.Array.i32 %6, ptr %coalesce.result.7
              br label %coalesce.end.2
            coalesce.fallback.1:
              store %Range.Array.i32 %4, ptr %coalesce.result.7
              br label %coalesce.end.2
            coalesce.end.2:
              %8 = load %Range.Array.i32, ptr %coalesce.result.7
              %chosen = alloca %Range.Array.i32
              store %Range.Array.i32 %8, ptr %chosen
              %9 = load %Range.Array.i32, ptr %chosen
              %10 = extractvalue %Range.Array.i32 %9, 0
              ret i32 %10
            }

            """
        )
    }

    @Test("Optional empty array emits nonnil aggregate")
    func optionalEmptyArrayEmitsNonnilAggregate() throws {
        let module = try emit(
            """
            @main {
                let maybe: Optional<[Int]>([])
                if maybe {
                    return 1
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Range_Array_i32 = type { i1, %Range.Array.i32 }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %3 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 1, 0
              %4 = insertvalue %Range.Optional._Range_Array_i32 %3, %Range.Array.i32 %2, 1
              %maybe = alloca %Range.Optional._Range_Array_i32
              store %Range.Optional._Range_Array_i32 %4, ptr %maybe
              %5 = load %Range.Optional._Range_Array_i32, ptr %maybe
              %6 = extractvalue %Range.Optional._Range_Array_i32 %5, 0
              br i1 %6, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 1
            if.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Integer arithmetic return emits LLVM instructions")
    func integerArithmeticReturnEmitsLLVMInstructions() throws {
        let module = try emit(
            """
            @main {
                return 5 + 2 * 3
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = mul i32 2, 3
                  %1 = add i32 5, %0
                  ret i32 %1
                """
            )
        )
    }

    @Test("Float comparison return emits fcmp")
    func floatComparisonReturnEmitsFCmp() throws {
        let module = try emit(
            """
            @main {
                return Float(1.0) > Float(0.5)
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = fcmp ogt double 1.0, 0.5
                  %1 = zext i1 %0 to i32
                  ret i32 %1
                """
            )
        )
    }

    @Test("Float constructor expression can initialize state")
    func floatConstructorExpressionCanInitializeState() throws {
        let module = try emit(
            """
            @main {
                state value: Float(2.5) + Float(1.5)
                return value > Float(3.0) ? 0 : 1
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = fadd double 2.5, 1.5
                  %value = alloca double
                  store double %0, ptr %value
                  %1 = load double, ptr %value
                  %2 = fcmp ogt double %1, 3.0
                  %3 = select i1 %2, i32 0, i32 1
                  ret i32 %3
                """
            )
        )
    }

    @Test("Float constructor expression can initialize local")
    func floatConstructorExpressionCanInitializeLocal() throws {
        let module = try emit(
            """
            @main {
                let value: Float(2.5) + Float(1.5)
                return value > Float(3.0) ? 0 : 1
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = fadd double 2.5, 1.5
                  %value = alloca double
                  store double %0, ptr %value
                  %1 = load double, ptr %value
                  %2 = fcmp ogt double %1, 3.0
                  %3 = select i1 %2, i32 0, i32 1
                  ret i32 %3
                """
            )
        )
    }

    @Test("Float remainder emits frem")
    func floatRemainderEmitsFRem() throws {
        let module = try emit(
            """
            @main {
                return Float(5.5) % Float(2.0) == Float(1.5)
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %0 = frem double 5.5, 2.0
                  %1 = fcmp oeq double %0, 1.5
                  %2 = zext i1 %1 to i32
                  ret i32 %2
                """
            )
        )
    }

    @Test("Float arithmetic function call emits double operations")
    func floatArithmeticFunctionCallEmitsDoubleOperations() throws {
        let module = try emit(
            """
            function ratio(value: Float): Float {
                return value / Float(2.0)
            }

            @main {
                let value: Float(3.0 + 1.5)
                if ratio(value: value) > Float(2.0) {
                    return 1
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            define double @ratio(double %value.arg) {
            entry:
              %value = alloca double
              store double %value.arg, ptr %value
              %0 = load double, ptr %value
              %1 = fdiv double %0, 2.0
              ret double %1
            }

            define i32 @main() {
            entry:
              %0 = fadd double 3.0, 1.5
              %value = alloca double
              store double %0, ptr %value
              %1 = load double, ptr %value
              %2 = call double @ratio(double %1)
              %3 = fcmp ogt double %2, 2.0
              br i1 %3, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 1
            if.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Float array element comparison emits double array load")
    func floatArrayElementComparisonEmitsDoubleArrayLoad() throws {
        let module = try emit(
            """
            @main {
                let values: [1.0, 2.5, 3.0]
                return values[1] > Float(2.0)
            }
            """
        )

        #expect(
            module == """
            %Range.Array.double = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 24)
              %1 = getelementptr inbounds double, ptr %0, i32 0
              store double 1.0, ptr %1
              %2 = getelementptr inbounds double, ptr %0, i32 1
              store double 2.5, ptr %2
              %3 = getelementptr inbounds double, ptr %0, i32 2
              store double 3.0, ptr %3
              %4 = insertvalue %Range.Array.double undef, i32 3, 0
              %5 = insertvalue %Range.Array.double %4, ptr %0, 1
              %values = alloca %Range.Array.double
              store %Range.Array.double %5, ptr %values
              %6 = load %Range.Array.double, ptr %values
              %7 = extractvalue %Range.Array.double %6, 1
              %8 = getelementptr inbounds double, ptr %7, i32 1
              %9 = load double, ptr %8
              %10 = fcmp ogt double %9, 2.0
              %11 = zext i1 %10 to i32
              ret i32 %11
            }

            """
        )
    }

    @Test("Integer arithmetic local return emits LLVM instructions")
    func integerArithmeticLocalReturnEmitsLLVMInstructions() throws {
        let module = try emit(
            """
            @main {
                let count: Int(5)
                let total: Int(count + 2)
                return total
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  %1 = add i32 %0, 2
                  %total = alloca i32
                  store i32 %1, ptr %total
                  %2 = load i32, ptr %total
                  ret i32 %2
                """
            )
        )
    }

    @Test("Mutable integer state assignment emits updated return")
    func mutableIntegerStateAssignmentEmitsUpdatedReturn() throws {
        let module = try emit(
            """
            @main {
                state count: Int(5)
                count: count + 2
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  %1 = add i32 %0, 2
                  store i32 %1, ptr %count
                  %2 = load i32, ptr %count
                  ret i32 %2
                """
            )
        )
    }

    @Test("If statement emits conditional branch")
    func ifStatementEmitsConditionalBranch() throws {
        let module = try emit(
            """
            @main {
                state count: Int(5)
                if count < 10 {
                    count: count + 1
                }
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  %1 = icmp slt i32 %0, 10
                  br i1 %1, label %if.then.1, label %if.end.0
                if.then.1:
                  %2 = load i32, ptr %count
                  %3 = add i32 %2, 1
                  store i32 %3, ptr %count
                  br label %if.end.0
                if.end.0:
                  %4 = load i32, ptr %count
                  ret i32 %4
                """
            )
        )
    }

    @Test("If else returns emit terminating branches")
    func ifElseReturnsEmitTerminatingBranches() throws {
        let module = try emit(
            """
            @main {
                let count: Int(5)
                if count < 10 {
                    return 1
                } else {
                    return 0
                }
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 5, ptr %count
                  %0 = load i32, ptr %count
                  %1 = icmp slt i32 %0, 10
                  br i1 %1, label %if.then.1, label %if.then.2
                if.then.1:
                  ret i32 1
                if.then.2:
                  ret i32 0
                """
            )
        )
    }

    @Test("While loop emits backedge")
    func whileLoopEmitsBackedge() throws {
        let module = try emit(
            """
            @main {
                state count: Int(0)
                while count < 3 {
                    count: count + 1
                }
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 0, ptr %count
                  br label %while.condition.0
                while.condition.0:
                  %0 = load i32, ptr %count
                  %1 = icmp slt i32 %0, 3
                  br i1 %1, label %while.body.1, label %while.end.2
                while.body.1:
                  %2 = load i32, ptr %count
                  %3 = add i32 %2, 1
                  store i32 %3, ptr %count
                  br label %while.condition.0
                while.end.2:
                  %4 = load i32, ptr %count
                  ret i32 %4
                """
            )
        )
    }

    @Test("Loop locals allocate once in the entry block")
    func loopLocalsAllocateOnceInEntryBlock() throws {
        let module = try emit(
            """
            @main {
                state count: Int(0)
                while count < 3 {
                    let next: Int(count + 1)
                    count: next
                }
                return count
            }
            """
        )

        let nextAlloca = "%next = alloca i32"
        #expect(module.components(separatedBy: nextAlloca).count == 2)
        #expect(module.contains("entry:\n  %count = alloca i32\n  %next = alloca i32\n"))
        #expect(!module.contains("while.body.1:\n  %next = alloca i32"))
    }

    @Test("Break emits branch to loop end")
    func breakEmitsBranchToLoopEnd() throws {
        let module = try emit(
            """
            @main {
                while Bool(true) {
                    break
                }
                return 4
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  br label %while.condition.0
                while.condition.0:
                  br i1 1, label %while.body.1, label %while.end.2
                while.body.1:
                  br label %while.end.2
                while.end.2:
                  ret i32 4
                """
            )
        )
    }

    @Test("Continue emits branch to loop condition")
    func continueEmitsBranchToLoopCondition() throws {
        let module = try emit(
            """
            @main {
                state count: Int(0)
                while count < 3 {
                    count: count + 1
                    continue
                    count: count + 10
                }
                return count
            }
            """
        )

        #expect(
            module == expectedMain(
                """
                  %count = alloca i32
                  store i32 0, ptr %count
                  br label %while.condition.0
                while.condition.0:
                  %0 = load i32, ptr %count
                  %1 = icmp slt i32 %0, 3
                  br i1 %1, label %while.body.1, label %while.end.2
                while.body.1:
                  %2 = load i32, ptr %count
                  %3 = add i32 %2, 1
                  store i32 %3, ptr %count
                  br label %while.condition.0
                while.end.2:
                  %4 = load i32, ptr %count
                  ret i32 %4
                """
            )
        )
    }

    @Test("Integer function call emits LLVM function")
    func integerFunctionCallEmitsLLVMFunction() throws {
        let module = try emit(
            """
            function add(lhs: Int, rhs: Int): Int {
                return lhs + rhs
            }

            @main {
                return add(lhs: 5, rhs: 2)
            }
            """
        )

        #expect(
            module == """
            define i32 @add(i32 %lhs.arg, i32 %rhs.arg) {
            entry:
              %lhs = alloca i32
              store i32 %lhs.arg, ptr %lhs
              %rhs = alloca i32
              store i32 %rhs.arg, ptr %rhs
              %0 = load i32, ptr %lhs
              %1 = load i32, ptr %rhs
              %2 = add i32 %0, %1
              ret i32 %2
            }

            define i32 @main() {
            entry:
              %0 = call i32 @add(i32 5, i32 2)
              ret i32 %0
            }

            """
        )
    }

    @Test("Function call fills trailing default argument")
    func functionCallFillsTrailingDefaultArgument() throws {
        let module = try emit(
            """
            function add(base: Int, amount: Int = 5): Int {
                return base + amount
            }

            @main {
                return add(base: 7)
            }
            """
        )

        #expect(
            module == """
            define i32 @add(i32 %base.arg, i32 %amount.arg) {
            entry:
              %base = alloca i32
              store i32 %base.arg, ptr %base
              %amount = alloca i32
              store i32 %amount.arg, ptr %amount
              %0 = load i32, ptr %base
              %1 = load i32, ptr %amount
              %2 = add i32 %0, %1
              ret i32 %2
            }

            define i32 @main() {
            entry:
              %0 = call i32 @add(i32 7, i32 5)
              ret i32 %0
            }

            """
        )
    }

    @Test("Function call skips labeled default argument")
    func functionCallSkipsLabeledDefaultArgument() throws {
        let module = try emit(
            """
            function add(base: Int = 2, amount: Int): Int {
                return base + amount
            }

            @main {
                return add(amount: 10)
            }
            """
        )

        #expect(
            module == """
            define i32 @add(i32 %base.arg, i32 %amount.arg) {
            entry:
              %base = alloca i32
              store i32 %base.arg, ptr %base
              %amount = alloca i32
              store i32 %amount.arg, ptr %amount
              %0 = load i32, ptr %base
              %1 = load i32, ptr %amount
              %2 = add i32 %0, %1
              ret i32 %2
            }

            define i32 @main() {
            entry:
              %0 = call i32 @add(i32 2, i32 10)
              ret i32 %0
            }

            """
        )
    }

    @Test("Function call fills Optional nil default argument")
    func functionCallFillsOptionalNilDefaultArgument() throws {
        let module = try emit(
            """
            function pick(value: Optional<Int> = nil): Int {
                return value ?? 4
            }

            @main {
                return pick()
            }
            """
        )

        #expect(
            module == """
            %Range.Optional.i32 = type { i1, i32 }

            define i32 @pick(%Range.Optional.i32 %value.arg) {
            entry:
              %value = alloca %Range.Optional.i32
              store %Range.Optional.i32 %value.arg, ptr %value
              %0 = load %Range.Optional.i32, ptr %value
              %1 = extractvalue %Range.Optional.i32 %0, 0
              %2 = extractvalue %Range.Optional.i32 %0, 1
              %coalesce.result.3 = alloca i32
              br i1 %1, label %coalesce.payload.0, label %coalesce.fallback.1
            coalesce.payload.0:
              store i32 %2, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.fallback.1:
              store i32 4, ptr %coalesce.result.3
              br label %coalesce.end.2
            coalesce.end.2:
              %4 = load i32, ptr %coalesce.result.3
              ret i32 %4
            }

            define i32 @main() {
            entry:
              %0 = insertvalue %Range.Optional.i32 undef, i1 0, 0
              %1 = call i32 @pick(%Range.Optional.i32 %0)
              ret i32 %1
            }

            """
        )
    }

    @Test("Generic integer function call emits specialized LLVM function")
    func genericIntegerFunctionCallEmitsSpecializedLLVMFunction() throws {
        let module = try emit(
            """
            function identity<T>(value: T): T {
                return value
            }

            @main {
                return identity<Int>(value: 11)
            }
            """
        )

        #expect(
            module == """
            define i32 @identity__Int(i32 %value.arg) {
            entry:
              %value = alloca i32
              store i32 %value.arg, ptr %value
              %0 = load i32, ptr %value
              ret i32 %0
            }

            define i32 @main() {
            entry:
              %0 = call i32 @identity__Int(i32 11)
              ret i32 %0
            }

            """
        )
    }

    @Test("Nested generic function call emits transitive specialized LLVM functions")
    func nestedGenericFunctionCallEmitsTransitiveSpecializedLLVMFunctions() throws {
        let module = try emit(
            """
            function identity<T>(value: T): T {
                return value
            }

            function forward<T>(value: T): T {
                return identity<T>(value: value)
            }

            @main {
                return forward<Int>(value: 12)
            }
            """
        )

        #expect(
            module == """
            define i32 @forward__Int(i32 %value.arg) {
            entry:
              %value = alloca i32
              store i32 %value.arg, ptr %value
              %0 = load i32, ptr %value
              %1 = call i32 @identity__Int(i32 %0)
              ret i32 %1
            }

            define i32 @identity__Int(i32 %value.arg) {
            entry:
              %value = alloca i32
              store i32 %value.arg, ptr %value
              %0 = load i32, ptr %value
              ret i32 %0
            }

            define i32 @main() {
            entry:
              %0 = call i32 @forward__Int(i32 12)
              ret i32 %0
            }

            """
        )
    }

    @Test("Generic function with generic enum parameter emits concrete enum specialization")
    func genericFunctionWithGenericEnumParameterEmitsConcreteEnumSpecialization() throws {
        let module = try emit(
            """
            enum ParseError {
                case failed
            }

            enum Result<Success, Failure> {
                case success(value: Success)
                case failure(error: Failure)
            }

            function unwrap<T>(result: Result<T, ParseError>, fallback: T): T {
                switch result {
                case .success(let value):
                    return value
                case .failure:
                    return fallback
                }
            }

            @main {
                return unwrap<Int>(result: .success(value: 14), fallback: 0)
            }
            """
        )

        #expect(
            module == """
            %Result_Int__ParseError_ = type { i32, i32, i32 }

            define i32 @unwrap__Int(%Result_Int__ParseError_ %result.arg, i32 %fallback.arg) {
            entry:
              %result = alloca %Result_Int__ParseError_
              store %Result_Int__ParseError_ %result.arg, ptr %result
              %fallback = alloca i32
              store i32 %fallback.arg, ptr %fallback
              %0 = load %Result_Int__ParseError_, ptr %result
              br label %switch.check.0.3
            switch.check.0.3:
              %1 = extractvalue %Result_Int__ParseError_ %0, 0
              %2 = icmp eq i32 %1, 0
              br i1 %2, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %3 = extractvalue %Result_Int__ParseError_ %0, 1
              %value.switch.binding.4 = alloca i32
              store i32 %3, ptr %value.switch.binding.4
              %5 = load i32, ptr %value.switch.binding.4
              ret i32 %5
            switch.check.1.4:
              %6 = extractvalue %Result_Int__ParseError_ %0, 0
              %7 = icmp eq i32 %6, 1
              br i1 %7, label %switch.case.2, label %switch.end.0
            switch.case.2:
              %8 = load i32, ptr %fallback
              ret i32 %8
            switch.end.0:
              ret i32 0
            }

            define i32 @main() {
            entry:
              %0 = insertvalue %Result_Int__ParseError_ undef, i32 0, 0
              %1 = insertvalue %Result_Int__ParseError_ %0, i32 14, 1
              %2 = call i32 @unwrap__Int(%Result_Int__ParseError_ %1, i32 0)
              ret i32 %2
            }

            """
        )
    }

    @Test("Generic construct field read emits concrete construct specialization")
    func genericConstructFieldReadEmitsConcreteConstructSpecialization() throws {
        let module = try emit(
            """
            construct Box<Value> {
                let value: Value
            }

            @main {
                let box: Box<Int>(value: 15)
                return box.value
            }
            """
        )

        #expect(
            module == """
            %Box_Int_ = type { i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Box_Int_ undef, i32 15, 0
              %box = alloca %Box_Int_
              store %Box_Int_ %0, ptr %box
              %1 = load %Box_Int_, ptr %box
              %2 = extractvalue %Box_Int_ %1, 0
              ret i32 %2
            }

            """
        )
    }

    @Test("Nested generic construct field read emits dependency layouts")
    func nestedGenericConstructFieldReadEmitsDependencyLayouts() throws {
        let module = try emit(
            """
            construct Pair<First, Second> {
                let first: First
                let second: Second
            }

            construct Box<Value> {
                let value: Value
            }

            @main {
                let box: Box<Pair<Int, Int>>(value: Pair<Int, Int>(first: 20, second: 21))
                return box.value.second
            }
            """
        )

        #expect(
            module == """
            %Box_Pair_Int__Int__ = type { %Pair_Int__Int_ }

            %Pair_Int__Int_ = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Pair_Int__Int_ undef, i32 20, 0
              %1 = insertvalue %Pair_Int__Int_ %0, i32 21, 1
              %2 = insertvalue %Box_Pair_Int__Int__ undef, %Pair_Int__Int_ %1, 0
              %box = alloca %Box_Pair_Int__Int__
              store %Box_Pair_Int__Int__ %2, ptr %box
              %3 = load %Box_Pair_Int__Int__, ptr %box
              %4 = extractvalue %Box_Pair_Int__Int__ %3, 0
              %5 = extractvalue %Pair_Int__Int_ %4, 1
              ret i32 %5
            }

            """
        )
    }

    @Test("Nested generic construct array element can read nested field")
    func nestedGenericConstructArrayElementCanReadNestedField() throws {
        let module = try emit(
            """
            construct Pair<First, Second> {
                let first: First
                let second: Second
            }

            construct Box<Value> {
                let value: Value
            }

            @main {
                let boxes: [Box<Pair<Int, Int>>]([
                    Box<Pair<Int, Int>>(value: Pair<Int, Int>(first: 22, second: 23)),
                    Box<Pair<Int, Int>>(value: Pair<Int, Int>(first: 24, second: 25))
                ])
                return boxes[1].value.second
            }
            """
        )

        #expect(
            module == """
            %Range.Array._Box_Pair_Int__Int__ = type { i32, ptr }
            declare ptr @malloc(i64)

            %Box_Pair_Int__Int__ = type { %Pair_Int__Int_ }

            %Pair_Int__Int_ = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Pair_Int__Int_ undef, i32 22, 0
              %1 = insertvalue %Pair_Int__Int_ %0, i32 23, 1
              %2 = insertvalue %Box_Pair_Int__Int__ undef, %Pair_Int__Int_ %1, 0
              %3 = insertvalue %Pair_Int__Int_ undef, i32 24, 0
              %4 = insertvalue %Pair_Int__Int_ %3, i32 25, 1
              %5 = insertvalue %Box_Pair_Int__Int__ undef, %Pair_Int__Int_ %4, 0
              %6 = call ptr @malloc(i64 16)
              %7 = getelementptr inbounds %Box_Pair_Int__Int__, ptr %6, i32 0
              store %Box_Pair_Int__Int__ %2, ptr %7
              %8 = getelementptr inbounds %Box_Pair_Int__Int__, ptr %6, i32 1
              store %Box_Pair_Int__Int__ %5, ptr %8
              %9 = insertvalue %Range.Array._Box_Pair_Int__Int__ undef, i32 2, 0
              %10 = insertvalue %Range.Array._Box_Pair_Int__Int__ %9, ptr %6, 1
              %boxes = alloca %Range.Array._Box_Pair_Int__Int__
              store %Range.Array._Box_Pair_Int__Int__ %10, ptr %boxes
              %11 = load %Range.Array._Box_Pair_Int__Int__, ptr %boxes
              %12 = extractvalue %Range.Array._Box_Pair_Int__Int__ %11, 1
              %13 = getelementptr inbounds %Box_Pair_Int__Int__, ptr %12, i32 1
              %14 = load %Box_Pair_Int__Int__, ptr %13
              %15 = extractvalue %Box_Pair_Int__Int__ %14, 0
              %16 = extractvalue %Pair_Int__Int_ %15, 1
              ret i32 %16
            }

            """
        )
    }

    @Test("Generic function with generic construct parameter emits concrete construct specialization")
    func genericFunctionWithGenericConstructParameterEmitsConcreteConstructSpecialization() throws {
        let module = try emit(
            """
            construct Box<Value> {
                let value: Value
            }

            function unwrap<T>(box: Box<T>): T {
                return box.value
            }

            @main {
                return unwrap<Int>(box: Box<Int>(value: 16))
            }
            """
        )

        #expect(
            module == """
            %Box_Int_ = type { i32 }

            define i32 @unwrap__Int(%Box_Int_ %box.arg) {
            entry:
              %box = alloca %Box_Int_
              store %Box_Int_ %box.arg, ptr %box
              %0 = load %Box_Int_, ptr %box
              %1 = extractvalue %Box_Int_ %0, 0
              ret i32 %1
            }

            define i32 @main() {
            entry:
              %0 = insertvalue %Box_Int_ undef, i32 16, 0
              %1 = call i32 @unwrap__Int(%Box_Int_ %0)
              ret i32 %1
            }

            """
        )
    }

    @Test("Generic construct array element can be read through concrete specialization")
    func genericConstructArrayElementCanBeReadThroughConcreteSpecialization() throws {
        let module = try emit(
            """
            construct Box<Value> {
                let value: Value
            }

            @main {
                let boxes: [Box<Int>]([Box<Int>(value: 17), Box<Int>(value: 18)])
                return boxes[1].value
            }
            """
        )

        #expect(
            module == """
            %Range.Array._Box_Int_ = type { i32, ptr }
            declare ptr @malloc(i64)

            %Box_Int_ = type { i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Box_Int_ undef, i32 17, 0
              %1 = insertvalue %Box_Int_ undef, i32 18, 0
              %2 = call ptr @malloc(i64 8)
              %3 = getelementptr inbounds %Box_Int_, ptr %2, i32 0
              store %Box_Int_ %0, ptr %3
              %4 = getelementptr inbounds %Box_Int_, ptr %2, i32 1
              store %Box_Int_ %1, ptr %4
              %5 = insertvalue %Range.Array._Box_Int_ undef, i32 2, 0
              %6 = insertvalue %Range.Array._Box_Int_ %5, ptr %2, 1
              %boxes = alloca %Range.Array._Box_Int_
              store %Range.Array._Box_Int_ %6, ptr %boxes
              %7 = load %Range.Array._Box_Int_, ptr %boxes
              %8 = extractvalue %Range.Array._Box_Int_ %7, 1
              %9 = getelementptr inbounds %Box_Int_, ptr %8, i32 1
              %10 = load %Box_Int_, ptr %9
              %11 = extractvalue %Box_Int_ %10, 0
              ret i32 %11
            }

            """
        )
    }

    @Test("Indexed generic construct array field assignment updates stored element")
    func indexedGenericConstructArrayFieldAssignmentUpdatesStoredElement() throws {
        let module = try emit(
            """
            construct Box<Value> {
                let value: Value
            }

            @main {
                state boxes: [Box<Int>]([Box<Int>(value: 17), Box<Int>(value: 18)])
                boxes[1].value: 19
                return boxes[1].value
            }
            """
        )

        #expect(
            module == """
            %Range.Array._Box_Int_ = type { i32, ptr }
            declare ptr @malloc(i64)

            %Box_Int_ = type { i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Box_Int_ undef, i32 17, 0
              %1 = insertvalue %Box_Int_ undef, i32 18, 0
              %2 = call ptr @malloc(i64 8)
              %3 = getelementptr inbounds %Box_Int_, ptr %2, i32 0
              store %Box_Int_ %0, ptr %3
              %4 = getelementptr inbounds %Box_Int_, ptr %2, i32 1
              store %Box_Int_ %1, ptr %4
              %5 = insertvalue %Range.Array._Box_Int_ undef, i32 2, 0
              %6 = insertvalue %Range.Array._Box_Int_ %5, ptr %2, 1
              %boxes = alloca %Range.Array._Box_Int_
              store %Range.Array._Box_Int_ %6, ptr %boxes
              %7 = load %Range.Array._Box_Int_, ptr %boxes
              %8 = extractvalue %Range.Array._Box_Int_ %7, 1
              %9 = getelementptr inbounds %Box_Int_, ptr %8, i32 1
              %10 = load %Box_Int_, ptr %9
              %11 = insertvalue %Box_Int_ %10, i32 19, 0
              store %Box_Int_ %11, ptr %9
              %12 = load %Range.Array._Box_Int_, ptr %boxes
              %13 = extractvalue %Range.Array._Box_Int_ %12, 1
              %14 = getelementptr inbounds %Box_Int_, ptr %13, i32 1
              %15 = load %Box_Int_, ptr %14
              %16 = extractvalue %Box_Int_ %15, 0
              ret i32 %16
            }

            """
        )
    }

    @Test("Boolean function call extends return for main")
    func booleanFunctionCallExtendsReturnForMain() throws {
        let module = try emit(
            """
            function isSmall(value: Int): Bool {
                return value < 10
            }

            @main {
                return isSmall(value: 5)
            }
            """
        )

        #expect(
            module == """
            define i1 @isSmall(i32 %value.arg) {
            entry:
              %value = alloca i32
              store i32 %value.arg, ptr %value
              %0 = load i32, ptr %value
              %1 = icmp slt i32 %0, 10
              ret i1 %1
            }

            define i32 @main() {
            entry:
              %0 = call i1 @isSmall(i32 5)
              %1 = zext i1 %0 to i32
              ret i32 %1
            }

            """
        )
    }

    @Test("Boolean parameter function call emits i1 parameter")
    func booleanParameterFunctionCallEmitsI1Parameter() throws {
        let module = try emit(
            """
            function choose(flag: Bool): Int {
                if flag {
                    return 9
                } else {
                    return 0
                }
            }

            @main {
                return choose(flag: Bool(true))
            }
            """
        )

        #expect(
            module == """
            define i32 @choose(i1 %flag.arg) {
            entry:
              %flag = alloca i1
              store i1 %flag.arg, ptr %flag
              %0 = load i1, ptr %flag
              br i1 %0, label %if.then.1, label %if.then.2
            if.then.1:
              ret i32 9
            if.then.2:
              ret i32 0
            }

            define i32 @main() {
            entry:
              %0 = call i32 @choose(i1 1)
              ret i32 %0
            }

            """
        )
    }

    @Test("Function body can call another function")
    func functionBodyCanCallAnotherFunction() throws {
        let module = try emit(
            """
            function add(lhs: Int, rhs: Int): Int {
                return lhs + rhs
            }

            function addOne(value: Int): Int {
                return add(lhs: value, rhs: 1)
            }

            @main {
                return addOne(value: 6)
            }
            """
        )

        #expect(
            module == """
            define i32 @add(i32 %lhs.arg, i32 %rhs.arg) {
            entry:
              %lhs = alloca i32
              store i32 %lhs.arg, ptr %lhs
              %rhs = alloca i32
              store i32 %rhs.arg, ptr %rhs
              %0 = load i32, ptr %lhs
              %1 = load i32, ptr %rhs
              %2 = add i32 %0, %1
              ret i32 %2
            }

            define i32 @addOne(i32 %value.arg) {
            entry:
              %value = alloca i32
              store i32 %value.arg, ptr %value
              %0 = load i32, ptr %value
              %1 = call i32 @add(i32 %0, i32 1)
              ret i32 %1
            }

            define i32 @main() {
            entry:
              %0 = call i32 @addOne(i32 6)
              ret i32 %0
            }

            """
        )
    }

    @Test("Void function call emits call statement")
    func voidFunctionCallEmitsCallStatement() throws {
        let module = try emit(
            """
            function step(): Void {
                return
            }

            function run(): Int {
                step()
                return 6
            }

            @main {
                return run()
            }
            """
        )

        #expect(
            module == """
            define void @step() {
            entry:
              ret void
            }

            define i32 @run() {
            entry:
              call void @step()
              ret i32 6
            }

            define i32 @main() {
            entry:
              %0 = call i32 @run()
              ret i32 %0
            }

            """
        )
    }

    @Test("Non-void function call statement discards return value")
    func nonVoidFunctionCallStatementDiscardsReturnValue() throws {
        let module = try emit(
            """
            function compute(): Int {
                return 4
            }

            @main {
                compute()
                return 7
            }
            """
        )

        #expect(
            module == """
            define i32 @compute() {
            entry:
              ret i32 4
            }

            define i32 @main() {
            entry:
              %0 = call i32 @compute()
              ret i32 7
            }

            """
        )
    }

    @Test("Construct field read emits struct extraction")
    func constructFieldReadEmitsStructExtraction() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            @main {
                let point: Point(x: 2, y: 5)
                return point.y
            }
            """
        )

        #expect(
            module == """
            %Point = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Point undef, i32 2, 0
              %1 = insertvalue %Point %0, i32 5, 1
              %point = alloca %Point
              store %Point %1, ptr %point
              %2 = load %Point, ptr %point
              %3 = extractvalue %Point %2, 1
              ret i32 %3
            }

            """
        )
    }

    @Test("Construct initialization fills omitted field defaults")
    func constructInitializationFillsOmittedFieldDefaults() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int(2)
                let y: Int(5)
            }

            @main {
                let point: Point()
                return point.y
            }
            """
        )

        #expect(
            module == """
            %Point = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Point undef, i32 2, 0
              %1 = insertvalue %Point %0, i32 5, 1
              %point = alloca %Point
              store %Point %1, ptr %point
              %2 = load %Point, ptr %point
              %3 = extractvalue %Point %2, 1
              ret i32 %3
            }

            """
        )
    }

    @Test("Construct initialization can skip defaulted field by label")
    func constructInitializationCanSkipDefaultedFieldByLabel() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int(2)
                let y: Int
            }

            @main {
                let point: Point(y: 5)
                return point.x + point.y
            }
            """
        )

        #expect(
            module == """
            %Point = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Point undef, i32 2, 0
              %1 = insertvalue %Point %0, i32 5, 1
              %point = alloca %Point
              store %Point %1, ptr %point
              %2 = load %Point, ptr %point
              %3 = extractvalue %Point %2, 0
              %4 = load %Point, ptr %point
              %5 = extractvalue %Point %4, 1
              %6 = add i32 %3, %5
              ret i32 %6
            }

            """
        )
    }

    @Test("Construct field assignment emits aggregate update")
    func constructFieldAssignmentEmitsAggregateUpdate() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            @main {
                state point: Point(x: 2, y: 5)
                point.x: 7
                return point.x
            }
            """
        )

        #expect(
            module == """
            %Point = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Point undef, i32 2, 0
              %1 = insertvalue %Point %0, i32 5, 1
              %point = alloca %Point
              store %Point %1, ptr %point
              %2 = load %Point, ptr %point
              %3 = insertvalue %Point %2, i32 7, 0
              store %Point %3, ptr %point
              %4 = load %Point, ptr %point
              %5 = extractvalue %Point %4, 0
              ret i32 %5
            }

            """
        )
    }

    @Test("Nested construct field assignment emits nested aggregate update")
    func nestedConstructFieldAssignmentEmitsNestedAggregateUpdate() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            construct Line {
                let start: Point
                let end: Point
            }

            @main {
                state line: Line(start: Point(x: 1, y: 2), end: Point(x: 3, y: 4))
                line.start.x: 9
                return line.start.x
            }
            """
        )

        #expect(
            module == """
            %Line = type { %Point, %Point }

            %Point = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Point undef, i32 1, 0
              %1 = insertvalue %Point %0, i32 2, 1
              %2 = insertvalue %Line undef, %Point %1, 0
              %3 = insertvalue %Point undef, i32 3, 0
              %4 = insertvalue %Point %3, i32 4, 1
              %5 = insertvalue %Line %2, %Point %4, 1
              %line = alloca %Line
              store %Line %5, ptr %line
              %6 = load %Line, ptr %line
              %7 = extractvalue %Line %6, 0
              %8 = insertvalue %Point %7, i32 9, 0
              %9 = insertvalue %Line %6, %Point %8, 0
              store %Line %9, ptr %line
              %10 = load %Line, ptr %line
              %11 = extractvalue %Line %10, 0
              %12 = extractvalue %Point %11, 0
              ret i32 %12
            }

            """
        )
    }

    @Test("Construct array field can be dynamically indexed")
    func constructArrayFieldCanBeDynamicallyIndexed() throws {
        let module = try emit(
            """
            construct Bag {
                let values: [Int]
            }

            @main {
                let bag: Bag(values: [1, 2, 3])
                let index: Int(1)
                return bag.values[index]
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Bag = type { %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %6 = insertvalue %Bag undef, %Range.Array.i32 %5, 0
              %bag = alloca %Bag
              store %Bag %6, ptr %bag
              %index = alloca i32
              store i32 1, ptr %index
              %7 = load %Bag, ptr %bag
              %8 = extractvalue %Bag %7, 0
              %9 = load i32, ptr %index
              %10 = extractvalue %Range.Array.i32 %8, 1
              %11 = getelementptr inbounds i32, ptr %10, i32 %9
              %12 = load i32, ptr %11
              ret i32 %12
            }

            """
        )
    }

    @Test("Construct array field can be initialized with empty array")
    func constructArrayFieldCanBeInitializedWithEmptyArray() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [])
                return bag.items.count
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Bag = type { %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %3 = insertvalue %Bag undef, %Range.Array.i32 %2, 0
              %bag = alloca %Bag
              store %Bag %3, ptr %bag
              %4 = load %Bag, ptr %bag
              %5 = extractvalue %Bag %4, 0
              %6 = extractvalue %Range.Array.i32 %5, 0
              ret i32 %6
            }

            """
        )
    }

    @Test("Construct array field default can be empty array")
    func constructArrayFieldDefaultCanBeEmptyArray() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]([])
            }

            @main {
                let bag: Bag()
                return bag.items.count
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Bag = type { %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %3 = insertvalue %Bag undef, %Range.Array.i32 %2, 0
              %bag = alloca %Bag
              store %Bag %3, ptr %bag
              %4 = load %Bag, ptr %bag
              %5 = extractvalue %Bag %4, 0
              %6 = extractvalue %Range.Array.i32 %5, 0
              ret i32 %6
            }

            """
        )
    }

    @Test("Construct array field can read isEmpty")
    func constructArrayFieldCanReadIsEmpty() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [])
                return bag.items.isEmpty ? 0 : 1
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Bag = type { %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %3 = insertvalue %Bag undef, %Range.Array.i32 %2, 0
              %bag = alloca %Bag
              store %Bag %3, ptr %bag
              %4 = load %Bag, ptr %bag
              %5 = extractvalue %Bag %4, 0
              %6 = extractvalue %Range.Array.i32 %5, 0
              %7 = icmp eq i32 %6, 0
              %8 = select i1 %7, i32 0, i32 1
              ret i32 %8
            }

            """
        )
    }

    @Test("Construct array field can be assigned empty array")
    func constructArrayFieldCanBeAssignedEmptyArray() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                state bag: Bag(items: [1])
                bag.items: []
                return bag.items.count
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Bag = type { %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 4)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = insertvalue %Range.Array.i32 undef, i32 1, 0
              %3 = insertvalue %Range.Array.i32 %2, ptr %0, 1
              %4 = insertvalue %Bag undef, %Range.Array.i32 %3, 0
              %bag = alloca %Bag
              store %Bag %4, ptr %bag
              %5 = call ptr @malloc(i64 0)
              %6 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %7 = insertvalue %Range.Array.i32 %6, ptr %5, 1
              %8 = load %Bag, ptr %bag
              %9 = insertvalue %Bag %8, %Range.Array.i32 %7, 0
              store %Bag %9, ptr %bag
              %10 = load %Bag, ptr %bag
              %11 = extractvalue %Bag %10, 0
              %12 = extractvalue %Range.Array.i32 %11, 0
              ret i32 %12
            }

            """
        )
    }

    @Test("Indexed construct array field can be assigned empty array")
    func indexedConstructArrayFieldCanBeAssignedEmptyArray() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                state bags: [Bag]([Bag(items: [1])])
                bags[0].items: []
                return bags[0].items.count
            }
            """
        )

        #expect(
            module == """
            %Range.Array._Bag = type { i32, ptr }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Bag = type { %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 4)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = insertvalue %Range.Array.i32 undef, i32 1, 0
              %3 = insertvalue %Range.Array.i32 %2, ptr %0, 1
              %4 = insertvalue %Bag undef, %Range.Array.i32 %3, 0
              %5 = call ptr @malloc(i64 16)
              %6 = getelementptr inbounds %Bag, ptr %5, i32 0
              store %Bag %4, ptr %6
              %7 = insertvalue %Range.Array._Bag undef, i32 1, 0
              %8 = insertvalue %Range.Array._Bag %7, ptr %5, 1
              %bags = alloca %Range.Array._Bag
              store %Range.Array._Bag %8, ptr %bags
              %9 = load %Range.Array._Bag, ptr %bags
              %10 = extractvalue %Range.Array._Bag %9, 1
              %11 = getelementptr inbounds %Bag, ptr %10, i32 0
              %12 = call ptr @malloc(i64 0)
              %13 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %14 = insertvalue %Range.Array.i32 %13, ptr %12, 1
              %15 = load %Bag, ptr %11
              %16 = insertvalue %Bag %15, %Range.Array.i32 %14, 0
              store %Bag %16, ptr %11
              %17 = load %Range.Array._Bag, ptr %bags
              %18 = extractvalue %Range.Array._Bag %17, 1
              %19 = getelementptr inbounds %Bag, ptr %18, i32 0
              %20 = load %Bag, ptr %19
              %21 = extractvalue %Bag %20, 0
              %22 = extractvalue %Range.Array.i32 %21, 0
              ret i32 %22
            }

            """
        )
    }

    @Test("Construct optional array field wraps value and can be assigned nil")
    func constructOptionalArrayFieldWrapsValueAndCanBeAssignedNil() throws {
        let module = try emit(
            """
            construct Box {
                let maybe: Optional<[Int]>
            }

            @main {
                state box: Box(maybe: [1])
                box.maybe: nil
                return box.maybe == nil ? 0 : 1
            }
            """
        )

        #expect(
            module == """
            %Range.Optional._Range_Array_i32 = type { i1, %Range.Array.i32 }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %Box = type { %Range.Optional._Range_Array_i32 }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 4)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = insertvalue %Range.Array.i32 undef, i32 1, 0
              %3 = insertvalue %Range.Array.i32 %2, ptr %0, 1
              %4 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 1, 0
              %5 = insertvalue %Range.Optional._Range_Array_i32 %4, %Range.Array.i32 %3, 1
              %6 = insertvalue %Box undef, %Range.Optional._Range_Array_i32 %5, 0
              %box = alloca %Box
              store %Box %6, ptr %box
              %7 = insertvalue %Range.Optional._Range_Array_i32 undef, i1 0, 0
              %8 = load %Box, ptr %box
              %9 = insertvalue %Box %8, %Range.Optional._Range_Array_i32 %7, 0
              store %Box %9, ptr %box
              %10 = load %Box, ptr %box
              %11 = extractvalue %Box %10, 0
              %12 = extractvalue %Range.Optional._Range_Array_i32 %11, 0
              %13 = icmp eq i1 %12, 0
              %14 = select i1 %13, i32 0, i32 1
              ret i32 %14
            }

            """
        )
    }

    @Test("Construct return value crosses function boundary")
    func constructReturnValueCrossesFunctionBoundary() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            function makePoint(): Point {
                return Point(x: 2, y: 5)
            }

            @main {
                let point: makePoint()
                return point.y
            }
            """
        )

        #expect(
            module == """
            %Point = type { i32, i32 }

            define %Point @makePoint() {
            entry:
              %0 = insertvalue %Point undef, i32 2, 0
              %1 = insertvalue %Point %0, i32 5, 1
              ret %Point %1
            }

            define i32 @main() {
            entry:
              %0 = call %Point @makePoint()
              %point = alloca %Point
              store %Point %0, ptr %point
              %1 = load %Point, ptr %point
              %2 = extractvalue %Point %1, 1
              ret i32 %2
            }

            """
        )
    }

    @Test("Construct parameter field read emits extraction")
    func constructParameterFieldReadEmitsExtraction() throws {
        let module = try emit(
            """
            construct Point {
                let x: Int
                let y: Int
            }

            function getY(point: Point): Int {
                return point.y
            }

            @main {
                return getY(point: Point(x: 2, y: 5))
            }
            """
        )

        #expect(
            module == """
            %Point = type { i32, i32 }

            define i32 @getY(%Point %point.arg) {
            entry:
              %point = alloca %Point
              store %Point %point.arg, ptr %point
              %0 = load %Point, ptr %point
              %1 = extractvalue %Point %0, 1
              ret i32 %1
            }

            define i32 @main() {
            entry:
              %0 = insertvalue %Point undef, i32 2, 0
              %1 = insertvalue %Point %0, i32 5, 1
              %2 = call i32 @getY(%Point %1)
              ret i32 %2
            }

            """
        )
    }

    @Test("Fixed integer array index emits aggregate extraction")
    func fixedIntegerArrayIndexEmitsAggregateExtraction() throws {
        let module = try emit(
            """
            @main {
                let numbers: [1, 2, 3]
                return numbers[1]
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %numbers = alloca %Range.Array.i32
              store %Range.Array.i32 %5, ptr %numbers
              %6 = load %Range.Array.i32, ptr %numbers
              %7 = extractvalue %Range.Array.i32 %6, 1
              %8 = getelementptr inbounds i32, ptr %7, i32 1
              %9 = load i32, ptr %8
              ret i32 %9
            }

            """
        )
    }

    @Test("Fixed integer array count emits constant count")
    func fixedIntegerArrayCountEmitsConstantCount() throws {
        let module = try emit(
            """
            @main {
                let numbers: [1, 2, 3]
                return numbers.count
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %numbers = alloca %Range.Array.i32
              store %Range.Array.i32 %5, ptr %numbers
              %6 = load %Range.Array.i32, ptr %numbers
              %7 = extractvalue %Range.Array.i32 %6, 0
              ret i32 %7
            }

            """
        )
    }

    @Test("Empty integer array local emits zero count")
    func emptyIntegerArrayLocalEmitsZeroCount() throws {
        let module = try emit(
            """
            @main {
                let values: [Int]([])
                return values.count
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %2, ptr %values
              %3 = load %Range.Array.i32, ptr %values
              %4 = extractvalue %Range.Array.i32 %3, 0
              ret i32 %4
            }

            """
        )
    }

    @Test("Empty integer array local emits true isEmpty")
    func emptyIntegerArrayLocalEmitsTrueIsEmpty() throws {
        let module = try emit(
            """
            @main {
                let values: [Int]([])
                return values.isEmpty ? 0 : 1
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %2, ptr %values
              %3 = load %Range.Array.i32, ptr %values
              %4 = extractvalue %Range.Array.i32 %3, 0
              %5 = icmp eq i32 %4, 0
              %6 = select i1 %5, i32 0, i32 1
              ret i32 %6
            }

            """
        )
    }

    @Test("Empty integer array literal decays to array parameter")
    func emptyIntegerArrayLiteralDecaysToArrayParameter() throws {
        let module = try emit(
            """
            function count(values: [Int]): Int {
                return values.count
            }

            @main {
                return count(values: [])
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @count(%Range.Array.i32 %values.arg) {
            entry:
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %values.arg, ptr %values
              %0 = load %Range.Array.i32, ptr %values
              %1 = extractvalue %Range.Array.i32 %0, 0
              ret i32 %1
            }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              %3 = call i32 @count(%Range.Array.i32 %2)
              ret i32 %3
            }

            """
        )
    }

    @Test("Empty integer array can be returned from function")
    func emptyIntegerArrayCanBeReturnedFromFunction() throws {
        let module = try emit(
            """
            function empty(): [Int] {
                return []
            }

            function count(values: [Int]): Int {
                return values.count
            }

            @main {
                return count(values: empty())
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define %Range.Array.i32 @empty() {
            entry:
              %0 = call ptr @malloc(i64 0)
              %1 = insertvalue %Range.Array.i32 undef, i32 0, 0
              %2 = insertvalue %Range.Array.i32 %1, ptr %0, 1
              ret %Range.Array.i32 %2
            }

            define i32 @count(%Range.Array.i32 %values.arg) {
            entry:
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %values.arg, ptr %values
              %0 = load %Range.Array.i32, ptr %values
              %1 = extractvalue %Range.Array.i32 %0, 0
              ret i32 %1
            }

            define i32 @main() {
            entry:
              %0 = call %Range.Array.i32 @empty()
              %1 = call i32 @count(%Range.Array.i32 %0)
              ret i32 %1
            }

            """
        )
    }

    @Test("Fixed integer array literal decays to array parameter")
    func fixedIntegerArrayLiteralDecaysToArrayParameter() throws {
        let module = try emit(
            """
            function second(numbers: [Int]): Int {
                return numbers[1]
            }

            @main {
                return second(numbers: [1, 2, 3])
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @second(%Range.Array.i32 %numbers.arg) {
            entry:
              %numbers = alloca %Range.Array.i32
              store %Range.Array.i32 %numbers.arg, ptr %numbers
              %0 = load %Range.Array.i32, ptr %numbers
              %1 = extractvalue %Range.Array.i32 %0, 1
              %2 = getelementptr inbounds i32, ptr %1, i32 1
              %3 = load i32, ptr %2
              ret i32 %3
            }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %6 = call i32 @second(%Range.Array.i32 %5)
              ret i32 %6
            }

            """
        )
    }

    @Test("Dynamic integer array index emits indexed load")
    func dynamicIntegerArrayIndexEmitsIndexedLoad() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                let index: Int(1)
                return values[index]
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %5, ptr %values
              %index = alloca i32
              store i32 1, ptr %index
              %6 = load %Range.Array.i32, ptr %values
              %7 = load i32, ptr %index
              %8 = extractvalue %Range.Array.i32 %6, 1
              %9 = getelementptr inbounds i32, ptr %8, i32 %7
              %10 = load i32, ptr %9
              ret i32 %10
            }

            """
        )
    }

    @Test("Array element member emits indexed load")
    func arrayElementMemberEmitsIndexedLoad() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                let index: Int(1)
                return values.element(index: index)
            }
            """
        )

        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("%values = alloca %Range.Array.i32"))
        #expect(module.contains("%index = alloca i32"))
        #expect(module.contains(" = load %Range.Array.i32, ptr %values"))
        #expect(module.contains(" = load i32, ptr %index"))
        #expect(module.contains(" = extractvalue %Range.Array.i32"))
        #expect(module.contains(" = getelementptr inbounds i32, ptr"))
        #expect(module.contains(" = load i32, ptr"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array append member mutates local array")
    func arrayAppendMemberMutatesLocalArray() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                values.append(element: 4)
                return values.count == 4 && values.element(index: 3) == 4 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = add i32"))
        #expect(module.contains(" = mul i64"))
        #expect(module.contains("call void @llvm.memcpy.p0.p0.i64"))
        #expect(module.contains("store i32 4, ptr"))
        #expect(module.contains("store %Range.Array.i32"))
        #expect(module.contains(" = icmp eq i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array append member mutates empty local array")
    func arrayAppendMemberMutatesEmptyLocalArray() throws {
        let module = try emit(
            """
            @main {
                let values: [Int]([])
                values.append(element: 7)
                return values.count == 1 && values.element(index: 0) == 7 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = call ptr @malloc(i64 0)"))
        #expect(module.contains("store i32 7, ptr"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array append member mutates construct field")
    func arrayAppendMemberMutatesConstructField() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [1, 2])
                bag.items.append(element: 3)
                return bag.items.count == 3 && bag.items.element(index: 2) == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = extractvalue %Bag"))
        #expect(module.contains(" = insertvalue %Bag"))
        #expect(module.contains("store %Bag"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array append member mutates empty construct field")
    func arrayAppendMemberMutatesEmptyConstructField() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [])
                bag.items.append(element: 9)
                return bag.items.count == 1 && bag.items.element(index: 0) == 9 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = call ptr @malloc(i64 0)"))
        #expect(module.contains("store i32 9, ptr"))
        #expect(module.contains("store %Bag"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array insert member mutates local array")
    func arrayInsertMemberMutatesLocalArray() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 3, 4]
                values.insert(element: 2, index: 1)
                return values.count == 4
                    && values.element(index: 1) == 2
                    && values.element(index: 2) == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = sub i64"))
        #expect(module.contains("store i32 2, ptr"))
        #expect(module.contains("store %Range.Array.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array insert member mutates construct field")
    func arrayInsertMemberMutatesConstructField() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [1, 3, 4])
                bag.items.insert(element: 2, index: 1)
                return bag.items.count == 4
                    && bag.items.element(index: 1) == 2
                    && bag.items.element(index: 2) == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = insertvalue %Bag"))
        #expect(module.contains("store i32 2, ptr"))
        #expect(module.contains("store %Bag"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array remove member mutates local array and returns removed element")
    func arrayRemoveMemberMutatesLocalArrayAndReturnsRemovedElement() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                let removed: Int(values.remove(index: 1))
                return removed == 2
                    && values.count == 2
                    && values.element(index: 1) == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = load i32, ptr"))
        #expect(module.contains(" = sub i32"))
        #expect(module.contains("store %Range.Array.i32"))
        #expect(module.contains("%removed = alloca i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array remove member mutates construct field and returns removed element")
    func arrayRemoveMemberMutatesConstructFieldAndReturnsRemovedElement() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [1, 2, 3])
                let removed: Int(bag.items.remove(index: 1))
                return removed == 2
                    && bag.items.count == 2
                    && bag.items.element(index: 1) == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = load i32, ptr"))
        #expect(module.contains(" = insertvalue %Bag"))
        #expect(module.contains("store %Bag"))
        #expect(module.contains("%removed = alloca i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array removeLast member mutates local array and returns optional element")
    func arrayRemoveLastMemberMutatesLocalArrayAndReturnsOptionalElement() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                let removed: Optional<Int>(values.removeLast())
                return (removed ?? 0) == 3
                    && values.count == 2
                    && values.element(index: 1) == 2 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("removeLast.empty"))
        #expect(module.contains("removeLast.value"))
        #expect(module.contains("%removed = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array removeLast member returns nil for empty local array")
    func arrayRemoveLastMemberReturnsNilForEmptyLocalArray() throws {
        let module = try emit(
            """
            @main {
                let values: [Int]([])
                let removed: Optional<Int>(values.removeLast())
                return removed == nil && values.count == 0 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("removeLast.empty"))
        #expect(module.contains("removeLast.value"))
        #expect(module.contains(" = insertvalue %Range.Optional.i32 undef, i1 0, 0"))
        #expect(module.contains("%removed = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array removeLast member mutates construct field and returns optional element")
    func arrayRemoveLastMemberMutatesConstructFieldAndReturnsOptionalElement() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [1, 2, 3])
                let removed: Optional<Int>(bag.items.removeLast())
                return (removed ?? 0) == 3
                    && bag.items.count == 2
                    && bag.items.element(index: 1) == 2 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains(" = insertvalue %Bag"))
        #expect(module.contains("%removed = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array first member returns optional first element")
    func arrayFirstMemberReturnsOptionalFirstElement() throws {
        let module = try emit(
            """
            @main {
                let values: [4, 5, 6]
                let first: Optional<Int>(values.first())
                return (first ?? 0) == 4 && values.count == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("arrayOptionalElement.empty"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%first = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array first member returns nil for empty local array")
    func arrayFirstMemberReturnsNilForEmptyLocalArray() throws {
        let module = try emit(
            """
            @main {
                let values: [Int]([])
                let first: Optional<Int>(values.first())
                return first == nil && values.count == 0 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("arrayOptionalElement.empty"))
        #expect(module.contains(" = insertvalue %Range.Optional.i32 undef, i1 0, 0"))
        #expect(module.contains("%first = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array last member returns optional last element")
    func arrayLastMemberReturnsOptionalLastElement() throws {
        let module = try emit(
            """
            @main {
                let values: [4, 5, 6]
                let last: Optional<Int>(values.last())
                return (last ?? 0) == 6 && values.count == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("arrayOptionalElement.empty"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%last = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array last member reads construct field")
    func arrayLastMemberReadsConstructField() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [4, 5, 6])
                let last: Optional<Int>(bag.items.last())
                return (last ?? 0) == 6 && bag.items.count == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.i32 = type { i1, i32 }"))
        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%last = alloca %Range.Optional.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("String array first member returns optional string")
    func stringArrayFirstMemberReturnsOptionalString() throws {
        let module = try emit(
            """
            @main {
                let values: [String]([String("alpha"), String("beta")])
                let first: Optional<String>(values.first())
                return (first ?? String("")) == String("alpha") ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.ptr = type { i1, ptr }"))
        #expect(module.contains("%Range.Array.ptr = type { i32, ptr }"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%first = alloca %Range.Optional.ptr"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("String array append and last member return optional string")
    func stringArrayAppendAndLastMemberReturnOptionalString() throws {
        let module = try emit(
            """
            @main {
                let values: [String]([String("alpha"), String("beta")])
                values.append(element: String("gamma"))
                let last: Optional<String>(values.last())
                return (last ?? String("")) == String("gamma")
                    && values.count == 3 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.ptr = type { i1, ptr }"))
        #expect(module.contains("%Range.Array.ptr = type { i32, ptr }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%last = alloca %Range.Optional.ptr"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("String array remove member mutates array and returns string")
    func stringArrayRemoveMemberMutatesArrayAndReturnsString() throws {
        let module = try emit(
            """
            @main {
                let values: [String]([String("alpha"), String("beta")])
                let removed: String(values.remove(index: 0))
                return removed == String("alpha")
                    && values.element(index: 0) == String("beta") ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array.ptr = type { i32, ptr }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%removed = alloca ptr"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("String array last member reads construct field")
    func stringArrayLastMemberReadsConstructField() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [String]
            }

            @main {
                let bag: Bag(items: [String("alpha"), String("beta")])
                let last: Optional<String>(bag.items.last())
                return (last ?? String("")) == String("beta")
                    && bag.items.count == 2 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.ptr = type { i1, ptr }"))
        #expect(module.contains("%Bag = type { %Range.Array.ptr }"))
        #expect(module.contains("%Range.Array.ptr = type { i32, ptr }"))
        #expect(module.contains("%last = alloca %Range.Optional.ptr"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("Construct array last member returns optional construct")
    func constructArrayLastMemberReturnsOptionalConstruct() throws {
        let module = try emit(
            """
            construct Box {
                let value: Int
            }

            @main {
                let boxes: [Box]([Box(value: 4), Box(value: 6)])
                let last: Optional<Box>(boxes.last())
                let fallback: Box(value: 0)
                let chosen: Box(last ?? fallback)
                return chosen.value == 6 && boxes.count == 2 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional._Box = type { i1, %Box }"))
        #expect(module.contains("%Range.Array._Box = type { i32, ptr }"))
        #expect(module.contains("%Box = type { i32 }"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%last = alloca %Range.Optional._Box"))
        #expect(module.contains("ret i32"))
    }

    @Test("Construct array append and last member return optional construct")
    func constructArrayAppendAndLastMemberReturnOptionalConstruct() throws {
        let module = try emit(
            """
            construct Box {
                let value: Int
            }

            @main {
                let boxes: [Box]([Box(value: 4)])
                boxes.append(element: Box(value: 9))
                let last: Optional<Box>(boxes.last())
                let fallback: Box(value: 0)
                let chosen: Box(last ?? fallback)
                return chosen.value == 9 && boxes.count == 2 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional._Box = type { i1, %Box }"))
        #expect(module.contains("%Range.Array._Box = type { i32, ptr }"))
        #expect(module.contains("%Box = type { i32 }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%last = alloca %Range.Optional._Box"))
        #expect(module.contains("ret i32"))
    }

    @Test("Construct array remove member mutates array and returns construct")
    func constructArrayRemoveMemberMutatesArrayAndReturnsConstruct() throws {
        let module = try emit(
            """
            construct Box {
                let value: Int
            }

            @main {
                let boxes: [Box]([Box(value: 4), Box(value: 6)])
                let removed: Box(boxes.remove(index: 0))
                let remaining: Box(boxes.element(index: 0))
                return removed.value == 4
                    && remaining.value == 6
                    && boxes.count == 1 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array._Box = type { i32, ptr }"))
        #expect(module.contains("%Box = type { i32 }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%removed = alloca %Box"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array clear member mutates local array")
    func arrayClearMemberMutatesLocalArray() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                values.clear()
                return values.isEmpty && values.count == 0 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains(" = call ptr @malloc(i64 0)"))
        #expect(module.contains(" = insertvalue %Range.Array.i32 undef, i32 0, 0"))
        #expect(module.contains("store %Range.Array.i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Array clear member mutates construct field")
    func arrayClearMemberMutatesConstructField() throws {
        let module = try emit(
            """
            construct Bag {
                let items: [Int]
            }

            @main {
                let bag: Bag(items: [1, 2, 3])
                bag.items.clear()
                return bag.items.isEmpty && bag.items.count == 0 ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Bag = type { %Range.Array.i32 }"))
        #expect(module.contains("%Range.Array.i32 = type { i32, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains(" = call ptr @malloc(i64 0)"))
        #expect(module.contains(" = insertvalue %Bag"))
        #expect(module.contains("store %Bag"))
        #expect(module.contains("ret i32"))
    }

    @Test("Nested integer array index emits nested loads")
    func nestedIntegerArrayIndexEmitsNestedLoads() throws {
        let module = try emit(
            """
            @main {
                let matrix: [[1, 2], [3, 4]]
                return matrix[1][0]
            }
            """
        )

        #expect(
            module == """
            %Range.Array._Range_Array_i32 = type { i32, ptr }
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 8)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = insertvalue %Range.Array.i32 undef, i32 2, 0
              %4 = insertvalue %Range.Array.i32 %3, ptr %0, 1
              %5 = call ptr @malloc(i64 8)
              %6 = getelementptr inbounds i32, ptr %5, i32 0
              store i32 3, ptr %6
              %7 = getelementptr inbounds i32, ptr %5, i32 1
              store i32 4, ptr %7
              %8 = insertvalue %Range.Array.i32 undef, i32 2, 0
              %9 = insertvalue %Range.Array.i32 %8, ptr %5, 1
              %10 = call ptr @malloc(i64 32)
              %11 = getelementptr inbounds %Range.Array.i32, ptr %10, i32 0
              store %Range.Array.i32 %4, ptr %11
              %12 = getelementptr inbounds %Range.Array.i32, ptr %10, i32 1
              store %Range.Array.i32 %9, ptr %12
              %13 = insertvalue %Range.Array._Range_Array_i32 undef, i32 2, 0
              %14 = insertvalue %Range.Array._Range_Array_i32 %13, ptr %10, 1
              %matrix = alloca %Range.Array._Range_Array_i32
              store %Range.Array._Range_Array_i32 %14, ptr %matrix
              %15 = load %Range.Array._Range_Array_i32, ptr %matrix
              %16 = extractvalue %Range.Array._Range_Array_i32 %15, 1
              %17 = getelementptr inbounds %Range.Array.i32, ptr %16, i32 1
              %18 = load %Range.Array.i32, ptr %17
              %19 = extractvalue %Range.Array.i32 %18, 1
              %20 = getelementptr inbounds i32, ptr %19, i32 0
              %21 = load i32, ptr %20
              ret i32 %21
            }

            """
        )
    }

    @Test("Ternary expression emits select")
    func ternaryExpressionEmitsSelect() throws {
        let module = try emit(
            """
            @main {
                let values: [1, 2, 3]
                let index: Int(2)
                return values[index] > 2 ? values[index] : 0
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %5, ptr %values
              %index = alloca i32
              store i32 2, ptr %index
              %6 = load %Range.Array.i32, ptr %values
              %7 = load i32, ptr %index
              %8 = extractvalue %Range.Array.i32 %6, 1
              %9 = getelementptr inbounds i32, ptr %8, i32 %7
              %10 = load i32, ptr %9
              %11 = icmp sgt i32 %10, 2
              %12 = load %Range.Array.i32, ptr %values
              %13 = load i32, ptr %index
              %14 = extractvalue %Range.Array.i32 %12, 1
              %15 = getelementptr inbounds i32, ptr %14, i32 %13
              %16 = load i32, ptr %15
              %17 = select i1 %11, i32 %16, i32 0
              ret i32 %17
            }

            """
        )
    }

    @Test("Ternary array return preserves array layout")
    func ternaryArrayReturnPreservesArrayLayout() throws {
        let module = try emit(
            """
            function choose(flag: Bool, first: [Int], second: [Int]): [Int] {
                return flag ? first : second
            }

            @main {
                let first: [1, 2, 3]
                let second: [4, 5, 6]
                let values: choose(flag: Bool(false), first: first, second: second)
                return values[1]
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define %Range.Array.i32 @choose(i1 %flag.arg, %Range.Array.i32 %first.arg, %Range.Array.i32 %second.arg) {
            entry:
              %flag = alloca i1
              store i1 %flag.arg, ptr %flag
              %first = alloca %Range.Array.i32
              store %Range.Array.i32 %first.arg, ptr %first
              %second = alloca %Range.Array.i32
              store %Range.Array.i32 %second.arg, ptr %second
              %0 = load i1, ptr %flag
              %1 = load %Range.Array.i32, ptr %first
              %2 = load %Range.Array.i32, ptr %second
              %3 = select i1 %0, %Range.Array.i32 %1, %Range.Array.i32 %2
              ret %Range.Array.i32 %3
            }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %first = alloca %Range.Array.i32
              store %Range.Array.i32 %5, ptr %first
              %6 = call ptr @malloc(i64 12)
              %7 = getelementptr inbounds i32, ptr %6, i32 0
              store i32 4, ptr %7
              %8 = getelementptr inbounds i32, ptr %6, i32 1
              store i32 5, ptr %8
              %9 = getelementptr inbounds i32, ptr %6, i32 2
              store i32 6, ptr %9
              %10 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %11 = insertvalue %Range.Array.i32 %10, ptr %6, 1
              %second = alloca %Range.Array.i32
              store %Range.Array.i32 %11, ptr %second
              %12 = load %Range.Array.i32, ptr %first
              %13 = load %Range.Array.i32, ptr %second
              %14 = call %Range.Array.i32 @choose(i1 0, %Range.Array.i32 %12, %Range.Array.i32 %13)
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %14, ptr %values
              %15 = load %Range.Array.i32, ptr %values
              %16 = extractvalue %Range.Array.i32 %15, 1
              %17 = getelementptr inbounds i32, ptr %16, i32 1
              %18 = load i32, ptr %17
              ret i32 %18
            }

            """
        )
    }

    @Test("Array parameter can be forwarded to another function")
    func arrayParameterCanBeForwardedToAnotherFunction() throws {
        let module = try emit(
            """
            function second(numbers: [Int]): Int {
                return numbers[1]
            }

            function forward(numbers: [Int]): Int {
                return second(numbers: numbers)
            }

            @main {
                return forward(numbers: [1, 2, 3])
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @second(%Range.Array.i32 %numbers.arg) {
            entry:
              %numbers = alloca %Range.Array.i32
              store %Range.Array.i32 %numbers.arg, ptr %numbers
              %0 = load %Range.Array.i32, ptr %numbers
              %1 = extractvalue %Range.Array.i32 %0, 1
              %2 = getelementptr inbounds i32, ptr %1, i32 1
              %3 = load i32, ptr %2
              ret i32 %3
            }

            define i32 @forward(%Range.Array.i32 %numbers.arg) {
            entry:
              %numbers = alloca %Range.Array.i32
              store %Range.Array.i32 %numbers.arg, ptr %numbers
              %0 = load %Range.Array.i32, ptr %numbers
              %1 = call i32 @second(%Range.Array.i32 %0)
              ret i32 %1
            }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %6 = call i32 @forward(%Range.Array.i32 %5)
              ret i32 %6
            }

            """
        )
    }

    @Test("Integer array can be returned from function")
    func integerArrayCanBeReturnedFromFunction() throws {
        let module = try emit(
            """
            function numbers(): [Int] {
                return [1, 2, 3]
            }

            @main {
                let values: numbers()
                return values[2]
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define %Range.Array.i32 @numbers() {
            entry:
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              ret %Range.Array.i32 %5
            }

            define i32 @main() {
            entry:
              %0 = call %Range.Array.i32 @numbers()
              %values = alloca %Range.Array.i32
              store %Range.Array.i32 %0, ptr %values
              %1 = load %Range.Array.i32, ptr %values
              %2 = extractvalue %Range.Array.i32 %1, 1
              %3 = getelementptr inbounds i32, ptr %2, i32 2
              %4 = load i32, ptr %3
              ret i32 %4
            }

            """
        )
    }

    @Test("For loop over integer array emits index loop")
    func forLoopOverIntegerArrayEmitsIndexLoop() throws {
        let module = try emit(
            """
            @main {
                state total: Int(0)
                for number in [1, 2, 3] {
                    total: total + number
                }
                return total
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            define i32 @main() {
            entry:
              %total = alloca i32
              store i32 0, ptr %total
              %0 = call ptr @malloc(i64 12)
              %1 = getelementptr inbounds i32, ptr %0, i32 0
              store i32 1, ptr %1
              %2 = getelementptr inbounds i32, ptr %0, i32 1
              store i32 2, ptr %2
              %3 = getelementptr inbounds i32, ptr %0, i32 2
              store i32 3, ptr %3
              %4 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %5 = insertvalue %Range.Array.i32 %4, ptr %0, 1
              %for.index.6 = alloca i32
              store i32 0, ptr %for.index.6
              %number.for.element.7 = alloca i32
              br label %for.condition.0
            for.condition.0:
              %8 = load i32, ptr %for.index.6
              %9 = extractvalue %Range.Array.i32 %5, 0
              %10 = icmp slt i32 %8, %9
              br i1 %10, label %for.body.1, label %for.end.3
            for.body.1:
              %11 = extractvalue %Range.Array.i32 %5, 1
              %12 = getelementptr inbounds i32, ptr %11, i32 %8
              %13 = load i32, ptr %12
              store i32 %13, ptr %number.for.element.7
              %14 = load i32, ptr %total
              %15 = load i32, ptr %number.for.element.7
              %16 = add i32 %14, %15
              store i32 %16, ptr %total
              br label %for.continue.2
            for.continue.2:
              %17 = load i32, ptr %for.index.6
              %18 = add i32 %17, 1
              store i32 %18, ptr %for.index.6
              br label %for.condition.0
            for.end.3:
              %19 = load i32, ptr %total
              ret i32 %19
            }

            """
        )
    }

    @Test("Integer switch emits branch chain")
    func integerSwitchEmitsBranchChain() throws {
        let module = try emit(
            """
            @main {
                let value: Int(2)
                switch value {
                case 1:
                    return 10
                case 2:
                    return 20
                default:
                    return 30
                }
            }
            """
        )

        #expect(
            module == """
            define i32 @main() {
            entry:
              %value = alloca i32
              store i32 2, ptr %value
              %0 = load i32, ptr %value
              br label %switch.check.0.3
            switch.check.0.3:
              %1 = icmp eq i32 %0, 1
              br i1 %1, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              ret i32 10
            switch.check.1.4:
              %2 = icmp eq i32 %0, 2
              br i1 %2, label %switch.case.2, label %switch.default.5
            switch.case.2:
              ret i32 20
            switch.default.5:
              ret i32 30
            }

            """
        )
    }

    @Test("Float switch emits floating equality branch chain")
    func floatSwitchEmitsFloatingEqualityBranchChain() throws {
        let module = try emit(
            """
            @main {
                let value: Float(1.5)
                switch value {
                case Float(0.5):
                    return 5
                case Float(1.5):
                    return 15
                default:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            define i32 @main() {
            entry:
              %value = alloca double
              store double 1.5, ptr %value
              %0 = load double, ptr %value
              br label %switch.check.0.3
            switch.check.0.3:
              %1 = fcmp oeq double %0, 0.5
              br i1 %1, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              ret i32 5
            switch.check.1.4:
              %2 = fcmp oeq double %0, 1.5
              br i1 %2, label %switch.case.2, label %switch.default.5
            switch.case.2:
              ret i32 15
            switch.default.5:
              ret i32 0
            }

            """
        )
    }

    @Test("String switch emits strcmp branch chain")
    func stringSwitchEmitsStrcmpBranchChain() throws {
        let module = try emit(
            """
            @main {
                let token: String(String("name"))
                switch token {
                case String("int"):
                    return 1
                case String("name"):
                    return 2
                default:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [5 x i8] c"\\6E\\61\\6D\\65\\00"
            @.str.1 = private unnamed_addr constant [4 x i8] c"\\69\\6E\\74\\00"
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %token = alloca ptr
              store ptr getelementptr inbounds ([5 x i8], ptr @.str.0, i32 0, i32 0), ptr %token
              %0 = load ptr, ptr %token
              br label %switch.check.0.3
            switch.check.0.3:
              %1 = call i32 @strcmp(ptr %0, ptr getelementptr inbounds ([4 x i8], ptr @.str.1, i32 0, i32 0))
              %2 = icmp eq i32 %1, 0
              br i1 %2, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              ret i32 1
            switch.check.1.4:
              %3 = call i32 @strcmp(ptr %0, ptr getelementptr inbounds ([5 x i8], ptr @.str.0, i32 0, i32 0))
              %4 = icmp eq i32 %3, 0
              br i1 %4, label %switch.case.2, label %switch.default.5
            switch.case.2:
              ret i32 2
            switch.default.5:
              ret i32 0
            }

            """
        )
    }

    @Test("No-payload enum switch emits integer tag comparisons")
    func noPayloadEnumSwitchEmitsIntegerTagComparisons() throws {
        let module = try emit(
            """
            enum TrafficLight {
                case red
                case yellow
                case green
            }

            @main {
                let light: TrafficLight(.green)
                switch light {
                case .red:
                    return 1
                case .yellow:
                    return 2
                case .green:
                    return 3
                }
            }
            """
        )

        #expect(
            module == """
            define i32 @main() {
            entry:
              %light = alloca i32
              store i32 2, ptr %light
              %0 = load i32, ptr %light
              br label %switch.check.0.4
            switch.check.0.4:
              %1 = icmp eq i32 %0, 0
              br i1 %1, label %switch.case.1, label %switch.check.1.5
            switch.case.1:
              ret i32 1
            switch.check.1.5:
              %2 = icmp eq i32 %0, 1
              br i1 %2, label %switch.case.2, label %switch.check.2.6
            switch.case.2:
              ret i32 2
            switch.check.2.6:
              %3 = icmp eq i32 %0, 2
              br i1 %3, label %switch.case.3, label %switch.end.0
            switch.case.3:
              ret i32 3
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Payload enum can compare against no-payload case")
    func payloadEnumCanCompareAgainstNoPayloadCase() throws {
        let module = try emit(
            """
            enum Token {
                case value(value: Int)
                case eof
            }

            @main {
                let token: Token(.eof)
                if token == .eof {
                    return 1
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            %Token = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %Token undef, i32 1, 0
              %token = alloca %Token
              store %Token %0, ptr %token
              %1 = load %Token, ptr %token
              %2 = extractvalue %Token %1, 0
              %3 = icmp eq i32 %2, 1
              br i1 %3, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 1
            if.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Associated-value enum switch binds payload")
    func associatedValueEnumSwitchBindsPayload() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let token: NumberToken(.value(value: 7))
                switch token {
                case .value(let number):
                    return number
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %NumberToken = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %NumberToken undef, i32 0, 0
              %1 = insertvalue %NumberToken %0, i32 7, 1
              %token = alloca %NumberToken
              store %NumberToken %1, ptr %token
              %2 = load %NumberToken, ptr %token
              br label %switch.check.0.3
            switch.check.0.3:
              %3 = extractvalue %NumberToken %2, 0
              %4 = icmp eq i32 %3, 0
              br i1 %4, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %5 = extractvalue %NumberToken %2, 1
              %number.switch.binding.6 = alloca i32
              store i32 %5, ptr %number.switch.binding.6
              %7 = load i32, ptr %number.switch.binding.6
              ret i32 %7
            switch.check.1.4:
              %8 = extractvalue %NumberToken %2, 0
              %9 = icmp eq i32 %8, 1
              br i1 %9, label %switch.case.2, label %switch.end.0
            switch.case.2:
              ret i32 0
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Mutable enum switch binding can be assigned")
    func mutableEnumSwitchBindingCanBeAssigned() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let token: NumberToken(.value(value: 7))
                switch token {
                case .value(state number):
                    number: number + 5
                    return number
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %NumberToken = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %NumberToken undef, i32 0, 0
              %1 = insertvalue %NumberToken %0, i32 7, 1
              %token = alloca %NumberToken
              store %NumberToken %1, ptr %token
              %2 = load %NumberToken, ptr %token
              br label %switch.check.0.3
            switch.check.0.3:
              %3 = extractvalue %NumberToken %2, 0
              %4 = icmp eq i32 %3, 0
              br i1 %4, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %5 = extractvalue %NumberToken %2, 1
              %number.switch.binding.6 = alloca i32
              store i32 %5, ptr %number.switch.binding.6
              %7 = load i32, ptr %number.switch.binding.6
              %8 = add i32 %7, 5
              store i32 %8, ptr %number.switch.binding.6
              %9 = load i32, ptr %number.switch.binding.6
              ret i32 %9
            switch.check.1.4:
              %10 = extractvalue %NumberToken %2, 0
              %11 = icmp eq i32 %10, 1
              br i1 %11, label %switch.case.2, label %switch.end.0
            switch.case.2:
              ret i32 0
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Mutable enum switch binding construct field can be assigned")
    func mutableEnumSwitchBindingConstructFieldCanBeAssigned() throws {
        let module = try emit(
            """
            construct Box {
                let value: Int
            }

            enum BoxToken {
                case value(value: Box)
                case eof
            }

            @main {
                let token: BoxToken(.value(value: Box(value: 8)))
                switch token {
                case .value(state box):
                    box.value: 13
                    return box.value
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %Box = type { i32 }

            %BoxToken = type { i32, %Box }

            define i32 @main() {
            entry:
              %0 = insertvalue %BoxToken undef, i32 0, 0
              %1 = insertvalue %Box undef, i32 8, 0
              %2 = insertvalue %BoxToken %0, %Box %1, 1
              %token = alloca %BoxToken
              store %BoxToken %2, ptr %token
              %3 = load %BoxToken, ptr %token
              br label %switch.check.0.3
            switch.check.0.3:
              %4 = extractvalue %BoxToken %3, 0
              %5 = icmp eq i32 %4, 0
              br i1 %5, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %6 = extractvalue %BoxToken %3, 1
              %box.switch.binding.7 = alloca %Box
              store %Box %6, ptr %box.switch.binding.7
              %8 = load %Box, ptr %box.switch.binding.7
              %9 = insertvalue %Box %8, i32 13, 0
              store %Box %9, ptr %box.switch.binding.7
              %10 = load %Box, ptr %box.switch.binding.7
              %11 = extractvalue %Box %10, 0
              ret i32 %11
            switch.check.1.4:
              %12 = extractvalue %BoxToken %3, 0
              %13 = icmp eq i32 %12, 1
              br i1 %13, label %switch.case.2, label %switch.end.0
            switch.case.2:
              ret i32 0
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Mutable enum switch binding array element can be assigned")
    func mutableEnumSwitchBindingArrayElementCanBeAssigned() throws {
        let module = try emit(
            """
            enum ValuesToken {
                case values(values: [Int])
                case eof
            }

            @main {
                let token: ValuesToken(.values(values: [4, 5, 6]))
                switch token {
                case .values(state values):
                    values[1]: 9
                    return values[1]
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %Range.Array.i32 = type { i32, ptr }
            declare ptr @malloc(i64)

            %ValuesToken = type { i32, %Range.Array.i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %ValuesToken undef, i32 0, 0
              %1 = call ptr @malloc(i64 12)
              %2 = getelementptr inbounds i32, ptr %1, i32 0
              store i32 4, ptr %2
              %3 = getelementptr inbounds i32, ptr %1, i32 1
              store i32 5, ptr %3
              %4 = getelementptr inbounds i32, ptr %1, i32 2
              store i32 6, ptr %4
              %5 = insertvalue %Range.Array.i32 undef, i32 3, 0
              %6 = insertvalue %Range.Array.i32 %5, ptr %1, 1
              %7 = insertvalue %ValuesToken %0, %Range.Array.i32 %6, 1
              %token = alloca %ValuesToken
              store %ValuesToken %7, ptr %token
              %8 = load %ValuesToken, ptr %token
              br label %switch.check.0.3
            switch.check.0.3:
              %9 = extractvalue %ValuesToken %8, 0
              %10 = icmp eq i32 %9, 0
              br i1 %10, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %11 = extractvalue %ValuesToken %8, 1
              %values.switch.binding.12 = alloca %Range.Array.i32
              store %Range.Array.i32 %11, ptr %values.switch.binding.12
              %13 = load %Range.Array.i32, ptr %values.switch.binding.12
              %14 = extractvalue %Range.Array.i32 %13, 1
              %15 = getelementptr inbounds i32, ptr %14, i32 1
              store i32 9, ptr %15
              %16 = load %Range.Array.i32, ptr %values.switch.binding.12
              %17 = extractvalue %Range.Array.i32 %16, 1
              %18 = getelementptr inbounds i32, ptr %17, i32 1
              %19 = load i32, ptr %18
              ret i32 %19
            switch.check.1.4:
              %20 = extractvalue %ValuesToken %8, 0
              %21 = icmp eq i32 %20, 1
              br i1 %21, label %switch.case.2, label %switch.end.0
            switch.case.2:
              ret i32 0
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Associated-value enum array element can switch on payload")
    func associatedValueEnumArrayElementCanSwitchOnPayload() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let tokens: [NumberToken]([.value(value: 4), .value(value: 6)])
                switch tokens[1] {
                case .value(let number):
                    return number
                case .eof:
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %Range.Array._NumberToken = type { i32, ptr }
            declare ptr @malloc(i64)

            %NumberToken = type { i32, i32 }

            define i32 @main() {
            entry:
              %0 = insertvalue %NumberToken undef, i32 0, 0
              %1 = insertvalue %NumberToken %0, i32 4, 1
              %2 = insertvalue %NumberToken undef, i32 0, 0
              %3 = insertvalue %NumberToken %2, i32 6, 1
              %4 = call ptr @malloc(i64 16)
              %5 = getelementptr inbounds %NumberToken, ptr %4, i32 0
              store %NumberToken %1, ptr %5
              %6 = getelementptr inbounds %NumberToken, ptr %4, i32 1
              store %NumberToken %3, ptr %6
              %7 = insertvalue %Range.Array._NumberToken undef, i32 2, 0
              %8 = insertvalue %Range.Array._NumberToken %7, ptr %4, 1
              %tokens = alloca %Range.Array._NumberToken
              store %Range.Array._NumberToken %8, ptr %tokens
              %9 = load %Range.Array._NumberToken, ptr %tokens
              %10 = extractvalue %Range.Array._NumberToken %9, 1
              %11 = getelementptr inbounds %NumberToken, ptr %10, i32 1
              %12 = load %NumberToken, ptr %11
              br label %switch.check.0.3
            switch.check.0.3:
              %13 = extractvalue %NumberToken %12, 0
              %14 = icmp eq i32 %13, 0
              br i1 %14, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %15 = extractvalue %NumberToken %12, 1
              %number.switch.binding.16 = alloca i32
              store i32 %15, ptr %number.switch.binding.16
              %17 = load i32, ptr %number.switch.binding.16
              ret i32 %17
            switch.check.1.4:
              %18 = extractvalue %NumberToken %12, 0
              %19 = icmp eq i32 %18, 1
              br i1 %19, label %switch.case.2, label %switch.end.0
            switch.case.2:
              ret i32 0
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Associated-value enum array last member returns optional enum")
    func associatedValueEnumArrayLastMemberReturnsOptionalEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let tokens: [NumberToken]([.value(value: 4), .value(value: 6)])
                let last: Optional<NumberToken>(tokens.last())
                let fallback: NumberToken(.eof)
                let chosen: NumberToken(last ?? fallback)
                switch chosen {
                case .value(let number):
                    return number == 6 && tokens.count == 2 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("%Range.Optional._NumberToken = type { i1, %NumberToken }"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%last = alloca %Range.Optional._NumberToken"))
        #expect(module.contains("ret i32"))
    }

    @Test("Associated-value enum array append and last member return optional enum")
    func associatedValueEnumArrayAppendAndLastMemberReturnOptionalEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let tokens: [NumberToken]([.value(value: 4)])
                tokens.append(element: .value(value: 9))
                let last: Optional<NumberToken>(tokens.last())
                let fallback: NumberToken(.eof)
                let chosen: NumberToken(last ?? fallback)
                switch chosen {
                case .value(let number):
                    return number == 9 && tokens.count == 2 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("%Range.Optional._NumberToken = type { i1, %NumberToken }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%last = alloca %Range.Optional._NumberToken"))
        #expect(module.contains("ret i32"))
    }

    @Test("Associated-value enum array remove member mutates array and returns enum")
    func associatedValueEnumArrayRemoveMemberMutatesArrayAndReturnsEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let tokens: [NumberToken]([.value(value: 4), .value(value: 6)])
                let removed: NumberToken(tokens.remove(index: 0))
                switch removed {
                case .value(let number):
                    return number == 4 && tokens.count == 1 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%removed = alloca %NumberToken"))
        #expect(module.contains("ret i32"))
    }

    @Test("Associated-value enum array removeLast member mutates array and returns optional enum")
    func associatedValueEnumArrayRemoveLastMemberMutatesArrayAndReturnsOptionalEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            @main {
                let tokens: [NumberToken]([.value(value: 4), .value(value: 6)])
                let removed: Optional<NumberToken>(tokens.removeLast())
                let fallback: NumberToken(.eof)
                let chosen: NumberToken(removed ?? fallback)
                switch chosen {
                case .value(let number):
                    return number == 6 && tokens.count == 1 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("%Range.Optional._NumberToken = type { i1, %NumberToken }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%removed = alloca %Range.Optional._NumberToken"))
        #expect(module.contains("ret i32"))
    }

    @Test("Construct enum array last member returns optional enum")
    func constructEnumArrayLastMemberReturnsOptionalEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            construct TokenBag {
                let tokens: [NumberToken]
            }

            @main {
                let bag: TokenBag(tokens: [.value(value: 4), .value(value: 6)])
                let last: Optional<NumberToken>(bag.tokens.last())
                let fallback: NumberToken(.eof)
                let chosen: NumberToken(last ?? fallback)
                switch chosen {
                case .value(let number):
                    return number == 6 && bag.tokens.count == 2 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%TokenBag = type { %Range.Array._NumberToken }"))
        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("%Range.Optional._NumberToken = type { i1, %NumberToken }"))
        #expect(module.contains("arrayOptionalElement.value"))
        #expect(module.contains("%last = alloca %Range.Optional._NumberToken"))
    }

    @Test("Construct enum array append and last member return optional enum")
    func constructEnumArrayAppendAndLastMemberReturnOptionalEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            construct TokenBag {
                let tokens: [NumberToken]
            }

            @main {
                let bag: TokenBag(tokens: [.value(value: 4)])
                bag.tokens.append(element: .value(value: 9))
                let last: Optional<NumberToken>(bag.tokens.last())
                let fallback: NumberToken(.eof)
                let chosen: NumberToken(last ?? fallback)
                switch chosen {
                case .value(let number):
                    return number == 9 && bag.tokens.count == 2 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%TokenBag = type { %Range.Array._NumberToken }"))
        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("%Range.Optional._NumberToken = type { i1, %NumberToken }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%last = alloca %Range.Optional._NumberToken"))
    }

    @Test("Construct enum array remove member mutates array and returns enum")
    func constructEnumArrayRemoveMemberMutatesArrayAndReturnsEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            construct TokenBag {
                let tokens: [NumberToken]
            }

            @main {
                let bag: TokenBag(tokens: [.value(value: 4), .value(value: 6)])
                let removed: NumberToken(bag.tokens.remove(index: 0))
                switch removed {
                case .value(let number):
                    return number == 4 && bag.tokens.count == 1 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%TokenBag = type { %Range.Array._NumberToken }"))
        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%removed = alloca %NumberToken"))
    }

    @Test("Construct enum array removeLast member mutates array and returns optional enum")
    func constructEnumArrayRemoveLastMemberMutatesArrayAndReturnsOptionalEnum() throws {
        let module = try emit(
            """
            enum NumberToken {
                case value(value: Int)
                case eof
            }

            construct TokenBag {
                let tokens: [NumberToken]
            }

            @main {
                let bag: TokenBag(tokens: [.value(value: 4), .value(value: 6)])
                let removed: Optional<NumberToken>(bag.tokens.removeLast())
                let fallback: NumberToken(.eof)
                let chosen: NumberToken(removed ?? fallback)
                switch chosen {
                case .value(let number):
                    return number == 6 && bag.tokens.count == 1 ? 0 : 1
                case .eof:
                    return 1
                }
            }
            """
        )

        #expect(module.contains("%TokenBag = type { %Range.Array._NumberToken }"))
        #expect(module.contains("%NumberToken = type { i32, i32 }"))
        #expect(module.contains("%Range.Array._NumberToken = type { i32, ptr }"))
        #expect(module.contains("%Range.Optional._NumberToken = type { i1, %NumberToken }"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("%removed = alloca %Range.Optional._NumberToken"))
    }

    @Test("Concrete generic enum switch binds payload")
    func concreteGenericEnumSwitchBindsPayload() throws {
        let module = try emit(
            """
            enum Result<Success, Failure> {
                case success(result: Success)
                case failure(cause: Failure)
            }

            enum ParseError {
                case invalid
            }

            function parse(): Result<Int, ParseError> {
                return .success(result: 9)
            }

            @main {
                switch parse() {
                case .success(let value):
                    return value
                case .failure(let error):
                    return 0
                }
            }
            """
        )

        #expect(
            module == """
            %Result_Int__ParseError_ = type { i32, i32, i32 }

            define %Result_Int__ParseError_ @parse() {
            entry:
              %0 = insertvalue %Result_Int__ParseError_ undef, i32 0, 0
              %1 = insertvalue %Result_Int__ParseError_ %0, i32 9, 1
              ret %Result_Int__ParseError_ %1
            }

            define i32 @main() {
            entry:
              %0 = call %Result_Int__ParseError_ @parse()
              br label %switch.check.0.3
            switch.check.0.3:
              %1 = extractvalue %Result_Int__ParseError_ %0, 0
              %2 = icmp eq i32 %1, 0
              br i1 %2, label %switch.case.1, label %switch.check.1.4
            switch.case.1:
              %3 = extractvalue %Result_Int__ParseError_ %0, 1
              %value.switch.binding.4 = alloca i32
              store i32 %3, ptr %value.switch.binding.4
              %5 = load i32, ptr %value.switch.binding.4
              ret i32 %5
            switch.check.1.4:
              %6 = extractvalue %Result_Int__ParseError_ %0, 0
              %7 = icmp eq i32 %6, 1
              br i1 %7, label %switch.case.2, label %switch.end.0
            switch.case.2:
              %8 = extractvalue %Result_Int__ParseError_ %0, 2
              %error.switch.binding.9 = alloca i32
              store i32 %8, ptr %error.switch.binding.9
              ret i32 0
            switch.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("String array parameter element can be returned and printed")
    func stringArrayParameterElementCanBeReturnedAndPrinted() throws {
        let module = try emit(
            """
            function first(values: [String]): String {
                return values[0]
            }

            @main {
                print(value: first(values: [String("Hi")]))
                return 0
            }
            """
        )

        #expect(
            module == """
            %Range.Array.ptr = type { i32, ptr }
            @.str.0 = private unnamed_addr constant [3 x i8] c"\\48\\69\\00"
            declare i32 @puts(ptr)
            declare ptr @malloc(i64)

            define ptr @first(%Range.Array.ptr %values.arg) {
            entry:
              %values = alloca %Range.Array.ptr
              store %Range.Array.ptr %values.arg, ptr %values
              %0 = load %Range.Array.ptr, ptr %values
              %1 = extractvalue %Range.Array.ptr %0, 1
              %2 = getelementptr inbounds ptr, ptr %1, i32 0
              %3 = load ptr, ptr %2
              ret ptr %3
            }

            define i32 @main() {
            entry:
              %0 = call ptr @malloc(i64 8)
              %1 = getelementptr inbounds ptr, ptr %0, i32 0
              store ptr getelementptr inbounds ([3 x i8], ptr @.str.0, i32 0, i32 0), ptr %1
              %2 = insertvalue %Range.Array.ptr undef, i32 1, 0
              %3 = insertvalue %Range.Array.ptr %2, ptr %0, 1
              %4 = call ptr @first(%Range.Array.ptr %3)
              %5 = call i32 @puts(ptr %4)
              ret i32 0
            }

            """
        )
    }

    @Test("String local emits global string pointer")
    func stringLocalEmitsGlobalStringPointer() throws {
        let module = try emit(
            """
            @main {
                let text: String("Hi")
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [3 x i8] c"\\48\\69\\00"

            define i32 @main() {
            entry:
              %text = alloca ptr
              store ptr getelementptr inbounds ([3 x i8], ptr @.str.0, i32 0, i32 0), ptr %text
              ret i32 0
            }

            """
        )
    }

    @Test("Print emits puts call")
    func printEmitsPutsCall() throws {
        let module = try emit(
            """
            @main {
                print(value: String("Hi"))
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [3 x i8] c"\\48\\69\\00"
            declare i32 @puts(ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @puts(ptr getelementptr inbounds ([3 x i8], ptr @.str.0, i32 0, i32 0))
              ret i32 0
            }

            """
        )
    }

    @Test("Print emits printf and bool text calls")
    func printEmitsPrintfAndBoolTextCalls() throws {
        let module = try emit(
            """
            @main {
                print(value: 7)
                print(value: Float(2.5))
                print(value: true)
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [4 x i8] c"\\25\\64\\0A\\00"
            @.str.1 = private unnamed_addr constant [4 x i8] c"\\25\\66\\0A\\00"
            @.str.2 = private unnamed_addr constant [5 x i8] c"\\74\\72\\75\\65\\00"
            @.str.3 = private unnamed_addr constant [6 x i8] c"\\66\\61\\6C\\73\\65\\00"
            declare i32 @puts(ptr)
            declare i32 @printf(ptr, ...)

            define i32 @main() {
            entry:
              %0 = call i32 (ptr, ...) @printf(ptr getelementptr inbounds ([4 x i8], ptr @.str.0, i32 0, i32 0), i32 7)
              %1 = call i32 (ptr, ...) @printf(ptr getelementptr inbounds ([4 x i8], ptr @.str.1, i32 0, i32 0), double 2.5)
              %2 = select i1 1, ptr getelementptr inbounds ([5 x i8], ptr @.str.2, i32 0, i32 0), ptr getelementptr inbounds ([6 x i8], ptr @.str.3, i32 0, i32 0)
              %3 = call i32 @puts(ptr %2)
              ret i32 0
            }

            """
        )
    }

    @Test("Defer emits cleanup before return")
    func deferEmitsCleanupBeforeReturn() throws {
        let module = try emit(
            """
            @main {
                @defer {
                    print(value: String("done"))
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [5 x i8] c"\\64\\6F\\6E\\65\\00"
            declare i32 @puts(ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @puts(ptr getelementptr inbounds ([5 x i8], ptr @.str.0, i32 0, i32 0))
              ret i32 0
            }

            """
        )
    }

    @Test("Defer emits cleanup in LIFO order")
    func deferEmitsCleanupInLIFOOrder() throws {
        let module = try emit(
            """
            @main {
                state count: Int(1)
                @defer {
                    count: count + 10
                }
                @defer {
                    count: count + 100
                }
                return count
            }
            """
        )

        #expect(
            module == """
            define i32 @main() {
            entry:
              %count = alloca i32
              store i32 1, ptr %count
              %0 = load i32, ptr %count
              %1 = load i32, ptr %count
              %2 = add i32 %1, 100
              store i32 %2, ptr %count
              %3 = load i32, ptr %count
              %4 = add i32 %3, 10
              store i32 %4, ptr %count
              ret i32 %0
            }

            """
        )
    }

    @Test("File exists emits access call")
    func fileExistsEmitsAccessCall() throws {
        let module = try emit(
            """
            @main {
                return fileExists(path: String("/dev/null"))
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [10 x i8] c"\\2F\\64\\65\\76\\2F\\6E\\75\\6C\\6C\\00"
            declare i32 @access(ptr, i32)

            define i32 @main() {
            entry:
              %0 = call i32 @access(ptr getelementptr inbounds ([10 x i8], ptr @.str.0, i32 0, i32 0), i32 0)
              %1 = icmp eq i32 %0, 0
              %2 = zext i1 %1 to i32
              ret i32 %2
            }

            """
        )
    }

    @Test("File exists can drive branch")
    func fileExistsCanDriveBranch() throws {
        let module = try emit(
            """
            @main {
                if fileExists(path: String("/dev/null")) {
                    return 7
                }
                return 1
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [10 x i8] c"\\2F\\64\\65\\76\\2F\\6E\\75\\6C\\6C\\00"
            declare i32 @access(ptr, i32)

            define i32 @main() {
            entry:
              %0 = call i32 @access(ptr getelementptr inbounds ([10 x i8], ptr @.str.0, i32 0, i32 0), i32 0)
              %1 = icmp eq i32 %0, 0
              br i1 %1, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 7
            if.end.0:
              ret i32 1
            }

            """
        )
    }

    @Test("Read file emits libc file read calls")
    func readFileEmitsLibcFileReadCalls() throws {
        let module = try emit(
            """
            @main {
                let text: String(readFile(path: String("fixture.txt")))
                print(value: text)
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [12 x i8] c"\\66\\69\\78\\74\\75\\72\\65\\2E\\74\\78\\74\\00"
            @.str.1 = private unnamed_addr constant [3 x i8] c"\\72\\62\\00"
            declare i32 @puts(ptr)
            declare ptr @malloc(i64)
            declare ptr @fopen(ptr, ptr)
            declare i32 @fseek(ptr, i64, i32)
            declare i64 @ftell(ptr)
            declare void @rewind(ptr)
            declare i64 @fread(ptr, i64, i64, ptr)
            declare i32 @fclose(ptr)

            define i32 @main() {
            entry:
              %0 = call ptr @fopen(ptr getelementptr inbounds ([12 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([3 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = call i32 @fseek(ptr %0, i64 0, i32 2)
              %2 = call i64 @ftell(ptr %0)
              call void @rewind(ptr %0)
              %3 = add i64 %2, 1
              %4 = call ptr @malloc(i64 %3)
              %5 = call i64 @fread(ptr %4, i64 1, i64 %2, ptr %0)
              %6 = getelementptr inbounds i8, ptr %4, i64 %5
              store i8 0, ptr %6
              %7 = call i32 @fclose(ptr %0)
              %text = alloca ptr
              store ptr %4, ptr %text
              %8 = load ptr, ptr %text
              %9 = call i32 @puts(ptr %8)
              ret i32 0
            }

            """
        )
    }

    @Test("Read file if exists returns optional string")
    func readFileIfExistsReturnsOptionalString() throws {
        let module = try emit(
            """
            @main {
                let text: Optional<String>(readFileIfExists(path: String("fixture.txt")))
                return (text ?? String("")) == String("hello") ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.ptr = type { i1, ptr }"))
        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare ptr @fopen(ptr, ptr)"))
        #expect(module.contains("declare i64 @fread(ptr, i64, i64, ptr)"))
        #expect(module.contains("declare i32 @fclose(ptr)"))
        #expect(module.contains("readFileIfExists.value"))
        #expect(module.contains("readFileIfExists.end"))
        #expect(module.contains("icmp ne ptr"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("Nil coalescing string member count emits strlen")
    func nilCoalescingStringMemberCountEmitsStrlen() throws {
        let module = try emit(
            """
            @main {
                let text: Optional<String>(readFileIfExists(path: String("fixture.txt")))
                return (text ?? String("")).count == 5 ? 0 : 1
            }
            """
        )

        #expect(module.contains("declare i64 @strlen(ptr)"))
        #expect(module.contains("trunc i64"))
        #expect(module.contains("readFileIfExists.value"))
        #expect(module.contains("ret i32"))
    }

    @Test("Read line emits stdin read loop")
    func readLineEmitsStdinReadLoop() throws {
        let module = try emit(
            """
            @main {
                let text: String(readLine())
                print(value: text)
                return text == String("hello") ? 0 : 1
            }
            """
        )

        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare i64 @read(i32, ptr, i64)"))
        #expect(module.contains("call ptr @malloc(i64 4096)"))
        #expect(module.contains("call i64 @read(i32 0, ptr"))
        #expect(module.contains("readLine.loop"))
        #expect(module.contains("readLine.byte"))
        #expect(module.contains("readLine.continue"))
        #expect(module.contains("icmp eq i8"))
        #expect(module.contains("declare i32 @puts(ptr)"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("Command line argument count emits Darwin argc lookup")
    func commandLineArgumentCountEmitsDarwinArgcLookup() throws {
        let module = try emit(
            """
            @main {
                return commandLineArgumentCount() == 2 ? 0 : 1
            }
            """
        )

        #expect(module.contains("declare ptr @_NSGetArgc()"))
        #expect(module.contains("call ptr @_NSGetArgc()"))
        #expect(module.contains("load i32"))
        #expect(module.contains("sub i32"))
        #expect(module.contains("ret i32"))
    }

    @Test("Command line argument emits optional string lookup")
    func commandLineArgumentEmitsOptionalStringLookup() throws {
        let module = try emit(
            """
            @main {
                let first: Optional<String>(commandLineArgument(index: 0))
                return (first ?? String("")) == String("alpha") ? 0 : 1
            }
            """
        )

        #expect(module.contains("%Range.Optional.ptr = type { i1, ptr }"))
        #expect(module.contains("declare ptr @_NSGetArgc()"))
        #expect(module.contains("declare ptr @_NSGetArgv()"))
        #expect(module.contains("commandLineArgument.value"))
        #expect(module.contains("commandLineArgument.end"))
        #expect(module.contains("getelementptr inbounds ptr"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains("ret i32"))
    }

    @Test("Write file emits libc file write calls")
    func writeFileEmitsLibcFileWriteCalls() throws {
        let module = try emit(
            """
            @main {
                writeFile(path: String("/tmp/range-write.txt"), text: String("hello"))
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [21 x i8] c"\\2F\\74\\6D\\70\\2F\\72\\61\\6E\\67\\65\\2D\\77\\72\\69\\74\\65\\2E\\74\\78\\74\\00"
            @.str.1 = private unnamed_addr constant [6 x i8] c"\\68\\65\\6C\\6C\\6F\\00"
            @.str.2 = private unnamed_addr constant [3 x i8] c"\\77\\62\\00"
            declare ptr @fopen(ptr, ptr)
            declare i32 @fclose(ptr)
            declare i64 @strlen(ptr)
            declare i64 @fwrite(ptr, i64, i64, ptr)

            define i32 @main() {
            entry:
              %0 = call ptr @fopen(ptr getelementptr inbounds ([21 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([3 x i8], ptr @.str.2, i32 0, i32 0))
              %1 = call i64 @strlen(ptr getelementptr inbounds ([6 x i8], ptr @.str.1, i32 0, i32 0))
              %2 = call i64 @fwrite(ptr getelementptr inbounds ([6 x i8], ptr @.str.1, i32 0, i32 0), i64 1, i64 %1, ptr %0)
              %3 = call i32 @fclose(ptr %0)
              ret i32 0
            }

            """
        )
    }

    @Test("String length emits strlen call")
    func stringLengthEmitsStrlenCall() throws {
        let module = try emit(
            """
            @main {
                return stringLength(value: String("hello"))
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [6 x i8] c"\\68\\65\\6C\\6C\\6F\\00"
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %0 = call i64 @strlen(ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0))
              %1 = trunc i64 %0 to i32
              ret i32 %1
            }

            """
        )
    }

    @Test("String prefix checks use the shared external runtime ABI")
    func stringPrefixChecksUseSharedExternalRuntimeABI() throws {
        let module = try emit(
            """
            @main {
                if stringHasPrefix(source: String("range"), start: 1, prefix: String("ang")) {
                    return 0
                }
                return 1
            }
            """
        )

        #expect(module.contains("declare i1 @stringHasPrefix(ptr, i32, ptr)"))
        #expect(module.contains("declare i32 @stringFindFrom(ptr, i32, ptr)"))
        #expect(module.contains("declare i32 @stringFindFirstOf(ptr, i32, ptr)"))
        #expect(module.contains("declare ptr @stringViewFrom(ptr, i32)"))
        #expect(module.contains("declare ptr @stringCharacterAt(ptr, i32)"))
        #expect(module.contains("declare i32 @stringByteAt(ptr, i32)"))
        #expect(module.contains("declare i32 @stringFindByteOf(ptr, i32, i32, i32, i32)"))
        #expect(module.contains("call i1 @stringHasPrefix(ptr"))
        #expect(!module.contains("define i1 @stringHasPrefix"))
    }

    @Test("String first-of searches use the shared external runtime ABI")
    func stringFirstOfSearchesUseSharedExternalRuntimeABI() throws {
        let module = try emit(
            """
            @main {
                return stringFindFirstOf(source: String("range|compiler~"), start: 0, characters: String("|~"))
            }
            """
        )

        #expect(module.contains("declare i32 @stringFindFirstOf(ptr, i32, ptr)"))
        #expect(module.contains("call i32 @stringFindFirstOf(ptr"))
        #expect(!module.contains("define i32 @stringFindFirstOf"))
    }

    @Test("TextBuffer uses the shared external runtime ABI")
    func textBufferUsesSharedExternalRuntimeABI() throws {
        let module = try emit(
            """
            @main {
                let buffer: TextBuffer(textBufferCreate(capacity: 2))
                textBufferAppend(buffer: buffer, text: String("range"))
                textBufferAppendInt(buffer: buffer, value: 56)
                textBufferAppendCharacter(buffer: buffer, source: String("!"), index: 0)
                let text: String(textBufferMaterialize(buffer: buffer))
                textBufferDestroy(buffer: buffer)
                return stringLength(value: text)
            }
            """
        )

        #expect(module.contains("declare ptr @textBufferCreate(i32)"))
        #expect(module.contains("declare i32 @textBufferAppend(ptr, ptr)"))
        #expect(module.contains("declare i32 @textBufferAppendInt(ptr, i32)"))
        #expect(module.contains("declare i32 @textBufferAppendCharacter(ptr, ptr, i32)"))
        #expect(module.contains("declare ptr @textBufferMaterialize(ptr)"))
        #expect(module.contains("declare i32 @textBufferDestroy(ptr)"))
        #expect(module.contains("call ptr @textBufferCreate(i32 2)"))
        #expect(module.contains("call i32 @textBufferAppend(ptr"))
        #expect(module.contains("call i32 @textBufferAppendInt(ptr"))
        #expect(module.contains("call i32 @textBufferAppendCharacter(ptr"))
        #expect(module.contains("call ptr @textBufferMaterialize(ptr"))
        #expect(module.contains("call i32 @textBufferDestroy(ptr"))
        #expect(!module.contains("define ptr @textBufferCreate"))
        #expect(!module.contains("define i32 @textBufferAppend"))
    }

    @Test("Literal string interpolation emits global string")
    func literalStringInterpolationEmitsGlobalString() throws {
        let module = try emit(
            """
            @main {
                return stringLength(value: String("count \\(7)"))
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [8 x i8] c"\\63\\6F\\75\\6E\\74\\20\\37\\00"
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %0 = call i64 @strlen(ptr getelementptr inbounds ([8 x i8], ptr @.str.0, i32 0, i32 0))
              %1 = trunc i64 %0 to i32
              ret i32 %1
            }

            """
        )
    }

    @Test("Dynamic string interpolation emits snprintf call")
    func dynamicStringInterpolationEmitsSnprintfCall() throws {
        let module = try emit(
            """
            @main {
                let count: Int(5)
                return stringLength(value: String("count \\(count)"))
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [9 x i8] c"\\63\\6F\\75\\6E\\74\\20\\25\\64\\00"
            declare i32 @snprintf(ptr, i64, ptr, ...)
            declare ptr @malloc(i64)
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %count = alloca i32
              store i32 5, ptr %count
              %0 = load i32, ptr %count
              %1 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr null, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @.str.0, i32 0, i32 0), i32 %0)
              %2 = sext i32 %1 to i64
              %3 = add i64 %2, 1
              %4 = call ptr @malloc(i64 %3)
              %5 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %4, i64 %3, ptr getelementptr inbounds ([9 x i8], ptr @.str.0, i32 0, i32 0), i32 %0)
              %6 = call i64 @strlen(ptr %4)
              %7 = trunc i64 %6 to i32
              ret i32 %7
            }

            """
        )
    }

    @Test("Self-appending string assignment does not free aliased storage")
    func selfAppendingStringAssignmentDoesNotFreeAliasedStorage() throws {
        let module = try emit(
            """
            @main {
                state output: String("")
                let alias: String(output)
                output: String("\\(output)next")
                print(value: alias)
                return 0
            }
            """
        )

        #expect(!module.contains("@malloc_size"))
        #expect(!module.contains("call void @free"))
        #expect(!module.contains("free.owned"))
    }

    @Test("Interpolated print emits puts call")
    func interpolatedPrintEmitsPutsCall() throws {
        let module = try emit(
            """
            @main {
                print(value: String("ready \\(true)"))
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [11 x i8] c"\\72\\65\\61\\64\\79\\20\\74\\72\\75\\65\\00"
            declare i32 @puts(ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @puts(ptr getelementptr inbounds ([11 x i8], ptr @.str.0, i32 0, i32 0))
              ret i32 0
            }

            """
        )
    }

    @Test("Read file string length can be returned")
    func readFileStringLengthCanBeReturned() throws {
        let module = try emit(
            """
            @main {
                let text: String(readFile(path: String("fixture.txt")))
                return stringLength(value: text)
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [12 x i8] c"\\66\\69\\78\\74\\75\\72\\65\\2E\\74\\78\\74\\00"
            @.str.1 = private unnamed_addr constant [3 x i8] c"\\72\\62\\00"
            declare ptr @malloc(i64)
            declare ptr @fopen(ptr, ptr)
            declare i32 @fseek(ptr, i64, i32)
            declare i64 @ftell(ptr)
            declare void @rewind(ptr)
            declare i64 @fread(ptr, i64, i64, ptr)
            declare i32 @fclose(ptr)
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %0 = call ptr @fopen(ptr getelementptr inbounds ([12 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([3 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = call i32 @fseek(ptr %0, i64 0, i32 2)
              %2 = call i64 @ftell(ptr %0)
              call void @rewind(ptr %0)
              %3 = add i64 %2, 1
              %4 = call ptr @malloc(i64 %3)
              %5 = call i64 @fread(ptr %4, i64 1, i64 %2, ptr %0)
              %6 = getelementptr inbounds i8, ptr %4, i64 %5
              store i8 0, ptr %6
              %7 = call i32 @fclose(ptr %0)
              %text = alloca ptr
              store ptr %4, ptr %text
              %8 = load ptr, ptr %text
              %9 = call i64 @strlen(ptr %8)
              %10 = trunc i64 %9 to i32
              ret i32 %10
            }

            """
        )
    }

    @Test("String count property emits strlen call")
    func stringCountPropertyEmitsStrlenCall() throws {
        let module = try emit(
            """
            @main {
                let text: String("hello")
                return text.count
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [6 x i8] c"\\68\\65\\6C\\6C\\6F\\00"
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %text = alloca ptr
              store ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0), ptr %text
              %0 = load ptr, ptr %text
              %1 = call i64 @strlen(ptr %0)
              %2 = trunc i64 %1 to i32
              ret i32 %2
            }

            """
        )
    }

    @Test("String isEmpty property emits strlen comparison")
    func stringIsEmptyPropertyEmitsStrlenComparison() throws {
        let module = try emit(
            """
            @main {
                let text: String("")
                return text.isEmpty ? 0 : 1
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [1 x i8] c"\\00"
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %text = alloca ptr
              store ptr getelementptr inbounds ([1 x i8], ptr @.str.0, i32 0, i32 0), ptr %text
              %0 = load ptr, ptr %text
              %1 = call i64 @strlen(ptr %0)
              %2 = icmp eq i64 %1, 0
              %3 = select i1 %2, i32 0, i32 1
              ret i32 %3
            }

            """
        )
    }

    @Test("String character member emits single-character allocation")
    func stringCharacterMemberEmitsSingleCharacterAllocation() throws {
        let module = try emit(
            """
            @main {
                let text: String("hello")
                return text.character(index: 1) == String("e") ? 0 : 1
            }
            """
        )

        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains(" = getelementptr inbounds i8, ptr %0, i64 %1"))
        #expect(module.contains(" = load i8, ptr %2"))
        #expect(module.contains(" = call ptr @malloc(i64 2)"))
        #expect(module.contains("store i8 %3, ptr %4"))
        #expect(module.contains(" = call i32 @strcmp(ptr %4, ptr getelementptr inbounds ([2 x i8], ptr @.str.1, i32 0, i32 0))"))
    }

    @Test("String substring member emits copied string allocation")
    func stringSubstringMemberEmitsCopiedStringAllocation() throws {
        let module = try emit(
            """
            @main {
                let text: String("hello")
                return text.substring(start: 1, end: 4) == String("ell") ? 0 : 1
            }
            """
        )

        #expect(module.contains("declare ptr @malloc(i64)"))
        #expect(module.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.contains("declare i32 @strcmp(ptr, ptr)"))
        #expect(module.contains(" = sub i32 4, 1"))
        #expect(module.contains(" = call ptr @malloc(i64 %4)"))
        #expect(module.contains("call void @llvm.memcpy.p0.p0.i64(ptr %5, ptr %6, i64 %3, i1 false)"))
        #expect(module.contains(" = call i32 @strcmp(ptr %5, ptr getelementptr inbounds ([4 x i8], ptr @.str.1, i32 0, i32 0))"))
    }

    @Test("Construct string field count emits strlen call")
    func constructStringFieldCountEmitsStrlenCall() throws {
        let module = try emit(
            """
            construct Box {
                let text: String
            }

            @main {
                let box: Box(text: String("hello"))
                return box.text.count
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [6 x i8] c"\\68\\65\\6C\\6C\\6F\\00"
            declare i64 @strlen(ptr)

            %Box = type { ptr }

            define i32 @main() {
            entry:
              %0 = insertvalue %Box undef, ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0), 0
              %box = alloca %Box
              store %Box %0, ptr %box
              %1 = load %Box, ptr %box
              %2 = extractvalue %Box %1, 0
              %3 = call i64 @strlen(ptr %2)
              %4 = trunc i64 %3 to i32
              ret i32 %4
            }

            """
        )
    }

    @Test("Construct string field isEmpty emits strlen comparison")
    func constructStringFieldIsEmptyEmitsStrlenComparison() throws {
        let module = try emit(
            """
            construct Box {
                let text: String
            }

            @main {
                let box: Box(text: String(""))
                return box.text.isEmpty ? 0 : 1
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [1 x i8] c"\\00"
            declare i64 @strlen(ptr)

            %Box = type { ptr }

            define i32 @main() {
            entry:
              %0 = insertvalue %Box undef, ptr getelementptr inbounds ([1 x i8], ptr @.str.0, i32 0, i32 0), 0
              %box = alloca %Box
              store %Box %0, ptr %box
              %1 = load %Box, ptr %box
              %2 = extractvalue %Box %1, 0
              %3 = call i64 @strlen(ptr %2)
              %4 = icmp eq i64 %3, 0
              %5 = select i1 %4, i32 0, i32 1
              ret i32 %5
            }

            """
        )
    }

    @Test("Read file count property can be returned")
    func readFileCountPropertyCanBeReturned() throws {
        let module = try emit(
            """
            @main {
                let text: String(readFile(path: String("fixture.txt")))
                return text.count
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [12 x i8] c"\\66\\69\\78\\74\\75\\72\\65\\2E\\74\\78\\74\\00"
            @.str.1 = private unnamed_addr constant [3 x i8] c"\\72\\62\\00"
            declare ptr @malloc(i64)
            declare ptr @fopen(ptr, ptr)
            declare i32 @fseek(ptr, i64, i32)
            declare i64 @ftell(ptr)
            declare void @rewind(ptr)
            declare i64 @fread(ptr, i64, i64, ptr)
            declare i32 @fclose(ptr)
            declare i64 @strlen(ptr)

            define i32 @main() {
            entry:
              %0 = call ptr @fopen(ptr getelementptr inbounds ([12 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([3 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = call i32 @fseek(ptr %0, i64 0, i32 2)
              %2 = call i64 @ftell(ptr %0)
              call void @rewind(ptr %0)
              %3 = add i64 %2, 1
              %4 = call ptr @malloc(i64 %3)
              %5 = call i64 @fread(ptr %4, i64 1, i64 %2, ptr %0)
              %6 = getelementptr inbounds i8, ptr %4, i64 %5
              store i8 0, ptr %6
              %7 = call i32 @fclose(ptr %0)
              %text = alloca ptr
              store ptr %4, ptr %text
              %8 = load ptr, ptr %text
              %9 = call i64 @strlen(ptr %8)
              %10 = trunc i64 %9 to i32
              ret i32 %10
            }

            """
        )
    }

    @Test("String equality emits strcmp call")
    func stringEqualityEmitsStrcmpCall() throws {
        let module = try emit(
            """
            @main {
                return String("hello") == String("hello")
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [6 x i8] c"\\68\\65\\6C\\6C\\6F\\00"
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @strcmp(ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0))
              %1 = icmp eq i32 %0, 0
              %2 = zext i1 %1 to i32
              ret i32 %2
            }

            """
        )
    }

    @Test("String constructor expression can initialize state")
    func stringConstructorExpressionCanInitializeState() throws {
        let module = try emit(
            """
            @main {
                state value: String("a") == String("a")
                return value ? 0 : 1
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [2 x i8] c"\\61\\00"
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @strcmp(ptr getelementptr inbounds ([2 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([2 x i8], ptr @.str.0, i32 0, i32 0))
              %1 = icmp eq i32 %0, 0
              %value = alloca i1
              store i1 %1, ptr %value
              %2 = load i1, ptr %value
              %3 = select i1 %2, i32 0, i32 1
              ret i32 %3
            }

            """
        )
    }

    @Test("String inequality emits strcmp call")
    func stringInequalityEmitsStrcmpCall() throws {
        let module = try emit(
            """
            @main {
                return String("hello") != String("world")
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [6 x i8] c"\\68\\65\\6C\\6C\\6F\\00"
            @.str.1 = private unnamed_addr constant [6 x i8] c"\\77\\6F\\72\\6C\\64\\00"
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @strcmp(ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([6 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = icmp ne i32 %0, 0
              %2 = zext i1 %1 to i32
              ret i32 %2
            }

            """
        )
    }

    @Test("Ordered string comparison emits strcmp predicate")
    func orderedStringComparisonEmitsStrcmpPredicate() throws {
        let module = try emit(
            """
            @main {
                return String("alpha") < String("omega")
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [6 x i8] c"\\61\\6C\\70\\68\\61\\00"
            @.str.1 = private unnamed_addr constant [6 x i8] c"\\6F\\6D\\65\\67\\61\\00"
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %0 = call i32 @strcmp(ptr getelementptr inbounds ([6 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([6 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = icmp slt i32 %0, 0
              %2 = zext i1 %1 to i32
              ret i32 %2
            }

            """
        )
    }

    @Test("Read file string equality can drive branch")
    func readFileStringEqualityCanDriveBranch() throws {
        let module = try emit(
            """
            @main {
                let text: String(readFile(path: String("fixture.txt")))
                if text != String("not same") {
                    return 1
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [12 x i8] c"\\66\\69\\78\\74\\75\\72\\65\\2E\\74\\78\\74\\00"
            @.str.1 = private unnamed_addr constant [3 x i8] c"\\72\\62\\00"
            @.str.2 = private unnamed_addr constant [9 x i8] c"\\6E\\6F\\74\\20\\73\\61\\6D\\65\\00"
            declare ptr @malloc(i64)
            declare ptr @fopen(ptr, ptr)
            declare i32 @fseek(ptr, i64, i32)
            declare i64 @ftell(ptr)
            declare void @rewind(ptr)
            declare i64 @fread(ptr, i64, i64, ptr)
            declare i32 @fclose(ptr)
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %0 = call ptr @fopen(ptr getelementptr inbounds ([12 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([3 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = call i32 @fseek(ptr %0, i64 0, i32 2)
              %2 = call i64 @ftell(ptr %0)
              call void @rewind(ptr %0)
              %3 = add i64 %2, 1
              %4 = call ptr @malloc(i64 %3)
              %5 = call i64 @fread(ptr %4, i64 1, i64 %2, ptr %0)
              %6 = getelementptr inbounds i8, ptr %4, i64 %5
              store i8 0, ptr %6
              %7 = call i32 @fclose(ptr %0)
              %text = alloca ptr
              store ptr %4, ptr %text
              %8 = load ptr, ptr %text
              %9 = call i32 @strcmp(ptr %8, ptr getelementptr inbounds ([9 x i8], ptr @.str.2, i32 0, i32 0))
              %10 = icmp ne i32 %9, 0
              br i1 %10, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 1
            if.end.0:
              ret i32 0
            }

            """
        )
    }

    @Test("Read file ordered string comparison can drive branch")
    func readFileOrderedStringComparisonCanDriveBranch() throws {
        let module = try emit(
            """
            @main {
                let text: String(readFile(path: String("fixture.txt")))
                if text < String("zzzz") {
                    return 1
                }
                return 0
            }
            """
        )

        #expect(
            module == """
            @.str.0 = private unnamed_addr constant [12 x i8] c"\\66\\69\\78\\74\\75\\72\\65\\2E\\74\\78\\74\\00"
            @.str.1 = private unnamed_addr constant [3 x i8] c"\\72\\62\\00"
            @.str.2 = private unnamed_addr constant [5 x i8] c"\\7A\\7A\\7A\\7A\\00"
            declare ptr @malloc(i64)
            declare ptr @fopen(ptr, ptr)
            declare i32 @fseek(ptr, i64, i32)
            declare i64 @ftell(ptr)
            declare void @rewind(ptr)
            declare i64 @fread(ptr, i64, i64, ptr)
            declare i32 @fclose(ptr)
            declare i32 @strcmp(ptr, ptr)

            define i32 @main() {
            entry:
              %0 = call ptr @fopen(ptr getelementptr inbounds ([12 x i8], ptr @.str.0, i32 0, i32 0), ptr getelementptr inbounds ([3 x i8], ptr @.str.1, i32 0, i32 0))
              %1 = call i32 @fseek(ptr %0, i64 0, i32 2)
              %2 = call i64 @ftell(ptr %0)
              call void @rewind(ptr %0)
              %3 = add i64 %2, 1
              %4 = call ptr @malloc(i64 %3)
              %5 = call i64 @fread(ptr %4, i64 1, i64 %2, ptr %0)
              %6 = getelementptr inbounds i8, ptr %4, i64 %5
              store i8 0, ptr %6
              %7 = call i32 @fclose(ptr %0)
              %text = alloca ptr
              store ptr %4, ptr %text
              %8 = load ptr, ptr %text
              %9 = call i32 @strcmp(ptr %8, ptr getelementptr inbounds ([5 x i8], ptr @.str.2, i32 0, i32 0))
              %10 = icmp slt i32 %9, 0
              br i1 %10, label %if.then.1, label %if.end.0
            if.then.1:
              ret i32 1
            if.end.0:
              ret i32 0
            }

            """
        )
    }

    private func emit(_ source: String) throws -> String {
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/Main.range",
                source: source,
                role: .project
            )
        )

        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        return try LLVMModuleEmitter().emit(program: program)
    }

    private func expectedMain(returning value: Int) -> String {
        expectedMain("  ret i32 \(value)")
    }

    private func expectedMain(_ body: String) -> String {
        """
        define i32 @main() {
        entry:
        \(body)
        }

        """
    }

    private func rangeCoreInputs() throws -> [SourceInput] {
        let rangeRoot = try repositoryRoot()
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
        let roots = [
            rangeRoot.appendingPathComponent("Core", isDirectory: true),
            rangeRoot.appendingPathComponent("Foundation", isDirectory: true),
            rangeRoot.appendingPathComponent("Lexer", isDirectory: true),
        ]

        return try roots.flatMap { root in
            try rangeFiles(in: root).map { file in
                SourceInput(
                    path: file.path,
                    source: try String(contentsOf: file, encoding: .utf8),
                    role: .core
                )
            }
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
            throw TestFixtureError.missingDirectory(root.path)
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory else {
                continue
            }
            guard url.pathExtension.lowercased() == "range" else {
                continue
            }
            files.append(url)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let packageFile = current
                .appendingPathComponent("RangeCompiler", isDirectory: true)
                .appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageFile.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw TestFixtureError.missingRepositoryRoot
    }
}

private enum TestFixtureError: Error, CustomStringConvertible {
    case missingDirectory(String)
    case missingRepositoryRoot

    var description: String {
        switch self {
        case .missingDirectory(let path):
            return "Missing directory: \(path)"
        case .missingRepositoryRoot:
            return "Could not locate repository root."
        }
    }
}
