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
