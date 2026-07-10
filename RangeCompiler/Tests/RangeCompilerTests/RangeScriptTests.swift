import Foundation
@testable import RangeCompiler
import Testing

@Suite("Range script", .serialized)
struct RangeScriptTests {
    @Test("Default run manifest covers every LLVM example")
    func defaultRunManifestCoversEveryLLVMExample() throws {
        let examplesDirectory = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM", isDirectory: true)
        let manifest = examplesDirectory.appendingPathComponent("run-manifest.tsv")
        let exampleNames = try rangeExampleNames(in: examplesDirectory)
        let manifestNames = try runManifestNames(in: manifest)

        #expect(manifestNames.count == 148)
        #expect(manifestNames == exampleNames)
    }

    @Test("Check command rejects unexpected arguments")
    func checkCommandRejectsUnexpectedArguments() throws {
        let result = try runRangeScript(arguments: ["check", "extra"])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("scripts/range check"))
    }

    @Test("Run manifest rejects empty manifests")
    func runManifestRejectsEmptyManifests() throws {
        let manifest = try temporaryManifest(contents: "")
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("LLVM run manifest has no runnable entries"))
    }

    @Test("Run manifest rejects duplicate entries")
    func runManifestRejectsDuplicateEntries() throws {
        let example = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/EmptyMain.range")
        let manifest = try temporaryManifest(
            contents: """
            \(example.path)\t0\t-\t-\t-
            \(example.path)\t0\t-\t-\t-

            """
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Duplicate LLVM run manifest entries"))
        #expect(result.stderr.contains("EmptyMain.range"))
    }

    @Test("Run manifest rejects invalid expected exit")
    func runManifestRejectsInvalidExpectedExit() throws {
        let example = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/EmptyMain.range")
        let manifest = try temporaryManifest(
            contents: "\(example.path)\t999\t-\t-\t-\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Invalid expected exit '999'"))
    }

    @Test("Run manifest rejects missing source files")
    func runManifestRejectsMissingSourceFiles() throws {
        let missing = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/Missing.range")
        let manifest = try temporaryManifest(
            contents: "\(missing.path)\t0\t-\t-\t-\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("references missing source"))
        #expect(result.stderr.contains("Missing.range"))
    }

    @Test("Run manifest checks executable stdout")
    func runManifestChecksExecutableStdout() throws {
        let example = try repositoryRoot()
            .appendingPathComponent("RangePlayground/Examples/LLVM/PrintString.range")
        let manifest = try temporaryManifest(
            contents: "\(example.path)\t0\t-\t-\tHello from Range\\n\n"
        )
        defer { try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent()) }

        let result = try runRangeScript(arguments: ["check-llvm-runs", manifest.path], timeout: 30)

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("LLVM run checks succeeded for 1 example(s)."))
        #expect(result.stderr.isEmpty)
    }

    @Test("Bootstrap compiler check scans Range compiler sources")
    func bootstrapCompilerCheckBuildsAndRunsRangeCompilerProgram() throws {
        let result = try runRangeScript(arguments: ["check-bootstrap-compiler"], timeout: 120)

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Bootstrap compiler check succeeded:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/llvm/Compiler"))
        #expect(result.stderr.isEmpty)
    }

    @Test("Stage 1 compiler check inventories parses validates and lowers Range compiler source set")
    func stage1CompilerCheckInventoriesParsesValidatesAndLowersRangeCompilerSourceSet() throws {
        let result = try runRangeScript(arguments: ["check-stage1-compiler"], timeout: 180)

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Stage 1 compiler source-set check succeeded:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/llvm/Compiler"))
        #expect(result.stderr.isEmpty)
    }

    @Test("Stage 2 compiler check emits candidate LLVM from Stage 1")
    func stage2CompilerCheckEmitsCandidateLLVMFromStage1() throws {
        let result = try runRangeScript(arguments: ["check-stage2-compiler"], timeout: 720)

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Stage 2 compiler candidate LLVM emitted:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/stage2/RangeCompiler.ll"))
        #expect(result.stdout.contains("Stage 2 compiler candidate linked:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/stage2/RangeCompiler"))
        #expect(result.stdout.contains("Linked Stage 2 compiler inventory check succeeded:"))
        #expect(result.stdout.contains("Linked Stage 2 compiler body-name check succeeded:"))
        #expect(result.stdout.contains("Linked Stage 2 compiler normal compile check succeeded:"))
        #expect(result.stdout.contains("Stage 3 compiler candidate LLVM emitted:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/stage3/RangeCompiler.ll"))
        #expect(result.stdout.contains("Stage 3 compiler candidate linked:"))
        #expect(result.stdout.contains("/Programs/Compiler/.range/Build/stage3/RangeCompiler"))
        #expect(result.stdout.contains("Linked Stage 2 compiler self-rebuild check succeeded:"))
        #expect(result.stderr.isEmpty)

        let candidate = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/RangeCompiler.ll")
        let executable = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/RangeCompiler")
        let runtimeSupport = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/RangeRuntime.c")
        let smokeLLVM = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/Smoke.ll")
        let smokeExecutable = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage2/Smoke")
        let stage3Candidate = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage3/RangeCompiler.ll")
        let stage3Executable = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/.range/Build/stage3/RangeCompiler")
        #expect(FileManager.default.fileExists(atPath: executable.path))
        #expect(FileManager.default.fileExists(atPath: runtimeSupport.path))
        #expect(FileManager.default.fileExists(atPath: smokeExecutable.path))
        #expect(FileManager.default.fileExists(atPath: stage3Candidate.path))
        #expect(FileManager.default.fileExists(atPath: stage3Executable.path))
        let llvmText = try String(contentsOf: candidate, encoding: .utf8)
        #expect(llvmText.contains("define ptr @compileRangeNativeSource(ptr %source)"))
        #expect(llvmText.contains("define ptr @compileRangeNativeSource(ptr %source) {\nentry:"))
        #expect(llvmText.contains("define i32 @main()"))
        #expect(llvmText.contains("call ptr @compileRangeNativeSource(ptr"))
        #expect(llvmText.contains("define ptr @compilerSourceSetBodyFunctionNames()"))
        #expect(llvmText.contains("define ptr @compilerSourceSetBodyFunctionNamesInventory()"))
        #expect(llvmText.contains("define i1 @compilerSourceRequestsSourceSetBodyFunctionNames(ptr %source)"))
        #expect(llvmText.contains("define ptr @compilerNativeSourceSetLLVMText(ptr %source)"))
        #expect(llvmText.contains("call ptr @compilerSourceSetProgramForLLVM(ptr"))
        #expect(llvmText.contains("define ptr @compilerSourceSetProgramForLLVM(ptr %source)"))
        #expect(llvmText.contains("define ptr @parseCompilerProgramForLLVMNamedBodies(ptr %source, ptr %bodyFunctionNames)"))
        #expect(llvmText.contains("define ptr @compilerCoreMainParsedBlock(ptr %program)"))
        #expect(llvmText.contains("define ptr @compilerCoreParseStatements(ptr %program, ptr %block)"))
        #expect(llvmText.contains("define ptr @parseCompilerStatementWithToken(ptr %program, ptr %cursor, ptr %maybeToken, i32 %bodyEnd)"))
        #expect(llvmText.contains("define ptr @parseCompilerIdentifierStatementWithTarget(ptr %cursor, ptr %token"))
        #expect(llvmText.contains("define ptr @parseCompilerAssignmentStatement(ptr %token"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerBlockWithLocals(ptr %program, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerBlockWithControl(ptr %program, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLoweredBlockRenderedBlocks(ptr %block)"))
        #expect(llvmText.contains("call ptr @compilerCoreLLVMLoweredBlockRenderedBlocks(ptr"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectLinearRecordBlockWithRecord(ptr %program, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectLinearRecordBlockWithIf(ptr %program, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectIfStatementRecord(ptr %program, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectIfStatementRecordWithElse(ptr %program"))
        #expect(llvmText.contains("define ptr @compilerCoreRenderedDirectIfElseStatementRecord(ptr %program"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectIfStatementRecordWithAfter(ptr %program"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerLinearStatementRecord(ptr %program, ptr %statementRecord"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerLinearStatementRecordReturn(ptr %program"))
        #expect(llvmText.contains("define ptr @compilerCoreRenderedDirectReturnBlock(ptr %program, ptr %parsedBlock"))
        #expect(llvmText.contains("define i1 @compilerCoreCanLowerLocalType(ptr %declarationRecords, ptr %typeName)"))
        #expect(llvmText.contains("define i32 @main() {\nentry:\n  %r0 = call i32 @commandLineArgumentCount()"))
        #expect(llvmText.contains("br i1 %r1, label %if0, label %after0"))
        #expect(llvmText.contains("after0:\n"))
        #expect(llvmText.contains("call ptr @commandLineArgument(i32 0)"))
        #expect(llvmText.contains("call ptr @readFile(ptr"))
        #expect(llvmText.contains("call ptr @compileRangeNativeSource(ptr"))
        #expect(!llvmText.contains("define ptr @compilerCoreMainParsedBlock(ptr %program) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define ptr @parseCompilerStatementWithToken(ptr %program, ptr %cursor, ptr %maybeToken, i32 %bodyEnd) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define ptr @compilerCoreLLVMLowerBlockWithControl(ptr %program, ptr %parsedBlock, ptr %initialLocalValues, i32 %initialTemporaryIndex, ptr %expectedReturnType, ptr %initialBlockLabel, ptr %fallthroughLabel, i32 %initialBranchIndex) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define ptr @compilerCoreLLVMLowerLinearStatementRecord(ptr %program, ptr %statementRecord, ptr %localValues, i32 %temporaryIndex, ptr %expectedReturnType) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define i32 @main() {\nentry:\n  ret i32 64\n}"))
        #expect(!llvmText.contains("add i1 %"))
        #expect(!llvmText.contains("stringEqual(ptr null"))
        #expect(!llvmText.contains("@character"))
        #expect(!llvmText.contains("@CompilerLLVMBasicBlock"))

        let smokeLLVMText = try String(contentsOf: smokeLLVM, encoding: .utf8)
        #expect(smokeLLVMText.contains("define i32 @main() {\nentry:"))
        #expect(smokeLLVMText.contains("ret i32 0"))
        #expect(!smokeLLVMText.contains("\\n"))

        let stage3LLVMText = try String(contentsOf: stage3Candidate, encoding: .utf8)
        #expect(stage3LLVMText.contains("define ptr @compileRangeNativeSource(ptr %source)"))
        #expect(stage3LLVMText.contains("define ptr @parseCompilerAssignmentStatement(ptr %token"))
        #expect(stage3LLVMText.contains("define ptr @compilerCoreRenderedDirectIfElseStatementRecord(ptr %program"))
        #expect(stage3LLVMText.contains("define i32 @main()"))
        #expect(stage3LLVMText.contains("call ptr @compileRangeNativeSource(ptr"))
        #expect(!stage3LLVMText.contains("stringEqual(ptr null"))
        #expect(!stage3LLVMText.contains("add i1 %"))
    }

    @Test("Native compiler lexer matches Swift bootstrap lexer corpus")
    func nativeCompilerLexerMatchesSwiftBootstrapLexerCorpus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let synthetic = directory.appendingPathComponent("LexerParity.range")
        try """
        @main {
            let escaped: `if`(1)
            let numbers: Pair(1, 2.5)
            let operators: Bool(a == b != c <= d >= e && f || g ?? h)
            let punctuation: Bag([a, b], #(value), value.path...)
            return 0
        }
        """.write(to: synthetic, atomically: true, encoding: .utf8)

        let root = try repositoryRoot()
        let sources = [
            root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range"),
            synthetic,
        ]

        for source in sources {
            let nativeTokens = try nativeCompilerLexerTokens(for: source)
            let swiftTokens = try swiftBootstrapLexerTokens(for: source)
            #expect(nativeTokens == swiftTokens, "Lexer mismatch for \(source.lastPathComponent)")
        }
    }

    @Test("Native compiler parses main block")
    func nativeCompilerParsesMainBlock() throws {
        let source = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range")
        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 90
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("ast\\tprogram\\thasMainBlock=true"))
        #expect(result.stdout.contains("ast\\tmainBlock"))
        #expect(result.stdout.contains("ast\\tblock\\tkind=main"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=if\\tcondition=binary(call(identifier(commandLineArgumentCount),arguments=[]),!=,integerLiteral(1))"))
        #expect(result.stdout.contains("statement0=kind=expression\\texpression=call(identifier(print),arguments=[argument0.value=call(identifier(String),arguments=[argument0=stringLiteral(\"usage: Compiler <input.range>\");]);])"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=return\\texpression=integerLiteral(0)"))
        #expect(result.stdout.contains("bodyStart="))
        #expect(result.stdout.contains("bodyEnd="))
    }

    @Test("Native compiler emits default AST and LLVM")
    func nativeCompilerEmitsDefaultASTAndLLVM() throws {
        let source = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range")
        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 90
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("ast\\tprogram\\thasMainBlock=true"))
        #expect(result.stdout.contains("ast\\tmainBlock"))
        #expect(result.stdout.contains("compilerCoreLLVM\\tmain"))
        #expect(result.stdout.contains("@.str."))
        #expect(result.stdout.contains("declare i32 @puts(ptr)"))
        #expect(result.stdout.contains("declare ptr @commandLineArgument(i32)"))
        #expect(result.stdout.contains("declare ptr @readFile(ptr)"))
        #expect(result.stdout.contains("define i32 @main()"))
        #expect(result.stdout.contains("call i32 @puts(ptr getelementptr inbounds"))
        #expect(result.stdout.contains("call i32 @commandLineArgumentCount()"))
        #expect(result.stdout.contains("call ptr @commandLineArgument(i32 0)"))
        #expect(result.stdout.contains("call ptr @readFile(ptr %r4)"))
        #expect(result.stdout.contains("call ptr @compileRangeSource(ptr"))
        #expect(result.stdout.contains("br i1"))
        #expect(result.stdout.contains("ret i32 0"))
        #expect(!result.stdout.contains("add i32 0, getelementptr"))
        #expect(!result.stdout.contains("call ptr @readFile(i32"))
    }

    @Test("Native compiler parses compiler-core statement AST")
    func nativeCompilerParsesCompilerCoreStatementAST() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerCoreAST.range")
        try """
        compilerCoreAST

        @main {
            let value: Int(7)
            let maybe: Optional<Int>(7)
            state values: [Int](1)
            let made: Int(makeValue(7))
            let total: Int(value + 1)
            let precedence: Int(value + 2 * 3)
            let leftAssoc: Int(value - 1 - 2)
            let fallback: Int(primary ?? secondary ?? value)
            let inverted: Bool(!flag)
            let negative: Int(-value)
            let grouped: Int((value + 2) * 3)
            let nestedText: String("value=\(String(""))")
            let delimiters: String("|~")
            object.build(value: 1)
            point.x: 9
            if value != 0 {
                let nested: Int(1)
                while value > 1 {
                    continue
                    return value
                }
            } else if value == 0 {
                return 2
            } else {
                return 0
            }
            return makeValue(value)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("ast\\tprogram\\thasMainBlock=true"))
        #expect(result.stdout.contains("ast\\tmainBlock"))
        #expect(result.stdout.contains("ast\\tblock\\tkind=main"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=value\\ttype=Int\\texpression=integerLiteral(7)"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=maybe\\ttype=Optional<Int>\\texpression=integerLiteral(7)"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=state\\tname=values\\ttype=[Int]\\texpression=integerLiteral(1)"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=made\\ttype=Int\\texpression=call(identifier(makeValue),arguments=[argument0=integerLiteral(7);])"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=total\\ttype=Int\\texpression=binary(identifier(value),+,integerLiteral(1))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=precedence\\ttype=Int\\texpression=binary(identifier(value),+,binary(integerLiteral(2),*,integerLiteral(3)))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=leftAssoc\\ttype=Int\\texpression=binary(binary(identifier(value),-,integerLiteral(1)),-,integerLiteral(2))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=fallback\\ttype=Int\\texpression=binary(identifier(primary),??,binary(identifier(secondary),??,identifier(value)))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=inverted\\ttype=Bool\\texpression=prefix(!,identifier(flag))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=negative\\ttype=Int\\texpression=prefix(-,identifier(value))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=grouped\\ttype=Int\\texpression=binary(binary(identifier(value),+,integerLiteral(2)),*,integerLiteral(3))"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=nestedText\\ttype=String"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=let\\tname=delimiters\\ttype=String\\texpression=stringLiteral(\"|~\")"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=expression\\texpression=call(member(identifier(object),build),arguments=[argument0.value=integerLiteral(1);])"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=assignment\\ttarget=member(identifier(point),x)\\texpression=integerLiteral(9)"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=if\\tcondition=binary(identifier(value),!=,integerLiteral(0))"))
        #expect(result.stdout.contains("bodyStatements=[statement0=kind=let\\tname=nested\\ttype=Int\\texpression=integerLiteral(1);statement1=kind=while\\tcondition=binary(identifier(value),>,integerLiteral(1))"))
        #expect(result.stdout.contains("bodyStatements=[statement0=kind=continue;statement1=kind=return\\texpression=identifier(value);]"))
        #expect(result.stdout.contains("elseStatements=[statement0=kind=if\\tcondition=binary(identifier(value),==,integerLiteral(0))"))
        #expect(result.stdout.contains("bodyStatements=[statement0=kind=return\\texpression=integerLiteral(2);]"))
        #expect(result.stdout.contains("elseStatements=[statement0=kind=return\\texpression=integerLiteral(0);]"))
        #expect(!result.stdout.contains("identifier(lse)"))
        #expect(!result.stdout.contains("identifier(f)"))
        #expect(result.stdout.contains("statement1=kind=return\\texpression=identifier(value);]"))
        #expect(result.stdout.contains("ast\\tstatement\\tkind=return\\texpression=call(identifier(makeValue),arguments=[argument0=identifier(value);])"))
    }

    @Test("Native compiler parses compiler-core function AST for compiler program")
    func nativeCompilerParsesCompilerCoreFunctionASTForCompilerProgram() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = try repositoryRoot()
        let compilerSource = try String(
            contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"),
            encoding: .utf8
        )
        let compilerCoreSource = try String(
            contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"),
            encoding: .utf8
        )
        let lexerSource = try String(
            contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"),
            encoding: .utf8
        )
        let source = directory.appendingPathComponent("CompilerProgramCoreAST.range")
        try """
        compilerCoreAST

        \(compilerSource)

        \(compilerCoreSource)

        \(lexerSource)
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("ast\\tconstruct\\tname=RangeLexedToken"))
        #expect(result.stdout.contains("members=[member0.name=kind,type=String;member1.name=start,type=Int;member2.name=end,type=Int;member3.name=text,type=String;]"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerProgram"))
        #expect(result.stdout.contains("member0.name=source,type=String;member1.name=hasMainBlock,type=Bool;member2.name=mainAttributeStart,type=Int;member3.name=mainBlock,type=CompilerBlock;member4.name=mainStatementRecords,type=String;member5.name=mainStatementSummary,type=String;member6.name=declarationRecords,type=String;member7.name=declarationSummary,type=String;member8.name=functionSummary,type=String;"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerParsedBlock"))
        #expect(result.stdout.contains("members=[member0.name=block,type=CompilerBlock;member1.name=statementRecords,type=String;member2.name=statementSummary,type=String;]"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMType"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMValue"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMInstruction"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMTerminator"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMModule"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMFunction"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMBasicBlock"))
        #expect(result.stdout.contains("ast\\tconstruct\\tname=CompilerLLVMLoweredBlock"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compileRangeSource"))
        #expect(result.stdout.contains("parameters=[parameter0.name=source,type=String;]"))
        #expect(result.stdout.contains("returnType=String"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreASTSummaryForProgram"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVMForProgram"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreSymbolSummaryForProgram"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreTypeSummaryForProgram"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreMainParsedBlock"))
        #expect(result.stdout.contains("returnType=CompilerParsedBlock"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreDeclarationSummary"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerConstructDeclaration"))
        #expect(result.stdout.contains("returnType=Optional<CompilerConstructDeclaration>"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerConstructMembers"))
        #expect(result.stdout.contains("returnType=CompilerConstructMembers"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerProgram"))
        #expect(result.stdout.contains("returnType=CompilerProgram"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerBlock"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;parameter1.name=block,type=CompilerBlock;]"))
        #expect(result.stdout.contains("returnType=CompilerParsedBlock"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVMLowerBlock"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;parameter1.name=parsedBlock,type=CompilerParsedBlock;]"))
        #expect(result.stdout.contains("returnType=CompilerLLVMLoweredBlock"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerFunctionParameters"))
        #expect(result.stdout.contains("returnType=CompilerFunctionParameters"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerStatement"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;parameter1.name=start,type=Int;parameter2.name=bodyEnd,type=Int;]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=parseCompilerControlBlockStatement"))
        #expect(result.stdout.contains("parameters=[parameter0.name=program,type=CompilerProgram;parameter1.name=cursor,type=CompilerTokenCursor;parameter2.name=keyword,type=RangeLexedToken;parameter3.name=bodyEnd,type=Int;]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreBlockStatementSummary"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreParseTypeReference"))
        #expect(result.stdout.contains("returnType=Optional<CompilerTypeReference>"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreParseMainBlock"))
        #expect(result.stdout.contains("returnType=Optional<CompilerMainBlock>"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVMModule"))
        #expect(result.stdout.contains("returnType=CompilerLLVMModule"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreRenderLLVMFunction"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreRenderLLVMInstructionRecords"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVMInstructionRecord"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=lexNextRangeToken"))
        #expect(result.stdout.contains("parameters=[parameter0.name=source,type=String;parameter1.name=start,type=Int;]"))
        #expect(result.stdout.contains("returnType=Optional<RangeLexedToken>"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=compilerCoreControlStatementBodyBlock"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=compilerCoreInferExpressionType"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=parseCompilerNestedBlockStatementSummary"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=compilerCoreFirstReturnStatement"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVMLowerReturnBlock"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=compilerCoreBlockSymbolSummary"))
        #expect(!result.stdout.contains("ast\\tfunction\\tname=compilerCoreBlockTypeSummary"))
    }

    @Test("Native compiler builds compiler-core symbol summary")
    func nativeCompilerBuildsCompilerCoreSymbolSummary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerCoreSymbols.range")
        try """
        compilerCoreSymbols

        construct Box {
            let value: Int
        }

        function makeValue(input: Int): Int {
            return input
        }

        @main {
            let value: Int(7)
            state cached: Optional<Int>(value)
            if value != 0 {
                let nested: Int(1)
            }
            return value
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("symbols\\tprogram"))
        #expect(result.stdout.contains("symbol\\tkind=construct\\tname=Box\\tscope=program\\tmembers=[member0.name=value,type=Int;]"))
        #expect(result.stdout.contains("symbol\\tkind=member\\tname=value\\tscope=construct:Box\\ttype=Int"))
        #expect(result.stdout.contains("symbol\\tkind=function\\tname=makeValue\\tscope=program\\tparameters=[parameter0.name=input,type=Int;]\\treturnType=Int"))
        #expect(result.stdout.contains("symbol\\tkind=parameter\\tname=input\\tscope=function:makeValue\\ttype=Int"))
        #expect(result.stdout.contains("symbol\\tkind=let\\tname=value\\tscope=main\\ttype=Int\\texpressionKind=integerLiteral"))
        #expect(result.stdout.contains("symbol\\tkind=state\\tname=cached\\tscope=main\\ttype=Optional<Int>\\texpressionKind=identifier"))
        #expect(result.stdout.contains("symbol\\tkind=let\\tname=nested\\tscope=main.if@"))
    }

    @Test("Native compiler builds compiler-core type summary")
    func nativeCompilerBuildsCompilerCoreTypeSummary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerCoreTypes.range")
        try """
        compilerCoreTypes

        construct Box {
            let value: Int
        }

        function makeValue(input: Int): Int {
            return input
        }

        function makeBox(input: Int): Box {
            return input
        }

        @main {
            let value: Int(7)
            let rawText: String("hello")
            let madeText: String(String("world"))
            let total: Int(value + 1)
            let made: Int(makeValue(value))
            let box: Box(makeBox(value))
            let boxed: Int(box.value)
            let direct: Int(makeBox(value).value)
            let flag: Bool(value != 0)
            let fallback: Int(maybe ?? value)
            if flag {
                let nested: Bool(!flag)
            }
            return total
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("types\\tprogram"))
        #expect(result.stdout.contains("type\\tkind=function\\tname=makeValue\\tscope=program\\treturnType=Int"))
        #expect(result.stdout.contains("type\\tkind=return\\tscope=function:makeValue\\tinferred=Int\\tdeclared=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=function\\tname=makeBox\\tscope=program\\treturnType=Box"))
        #expect(result.stdout.contains("type\\tkind=return\\tscope=function:makeBox\\tinferred=Int\\tdeclared=Box\\tstatus=mismatch"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=value\\tscope=main\\tdeclared=Int\\tinferred=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=rawText\\tscope=main\\tdeclared=String\\tinferred=String\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=madeText\\tscope=main\\tdeclared=String\\tinferred=String\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=total\\tscope=main\\tdeclared=Int\\tinferred=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=made\\tscope=main\\tdeclared=Int\\tinferred=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=box\\tscope=main\\tdeclared=Box\\tinferred=Box\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=boxed\\tscope=main\\tdeclared=Int\\tinferred=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=direct\\tscope=main\\tdeclared=Int\\tinferred=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=flag\\tscope=main\\tdeclared=Bool\\tinferred=Bool\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=fallback\\tscope=main\\tdeclared=Int\\tinferred=Int\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=if\\tscope=main\\tcondition=Bool\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=let\\tname=nested\\tscope=main.if@"))
        #expect(result.stdout.contains("declared=Bool\\tinferred=Bool\\tstatus=ok"))
        #expect(result.stdout.contains("type\\tkind=return\\tscope=main\\tinferred=Int\\tdeclared=Int\\tstatus=ok"))
    }

    @Test("Native compiler parses structural type references")
    func nativeCompilerParsesStructuralTypeReferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("StructuralTypeReferences.range")
        try """
        compilerCoreAST

        function maybeToken(): Optional<RangeLexedToken> {
            return nil
        }

        function tokenArray(): [RangeLexedToken] {
            return []
        }

        function maybeTokenArray(): Optional<[RangeLexedToken]> {
            return nil
        }

        function maybeString(): String? {
            return nil
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("ast\\tfunction\\tname=maybeToken"))
        #expect(result.stdout.contains("returnType=Optional<RangeLexedToken>"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=tokenArray"))
        #expect(result.stdout.contains("returnType=[RangeLexedToken]"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=maybeTokenArray"))
        #expect(result.stdout.contains("returnType=Optional<[RangeLexedToken]>"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=maybeString"))
        #expect(result.stdout.contains("returnType=String?"))
    }

    @Test("Native compiler emits string literal LLVM from AST")
    func nativeCompilerEmitsStringLiteralLLVMFromAST() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerCoreStringLLVM.range")
        try """
        compilerCoreLLVM

        @main {
            let text: String(String("hello\\n"))
            print(value: text)
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("compilerCoreLLVM\\tmain"))
        #expect(result.stdout.contains("constant [7 x i8]"))
        #expect(result.stdout.contains("hello\\0A\\00"))
        #expect(result.stdout.contains("declare i32 @puts(ptr)"))
        #expect(result.stdout.contains("define i32 @main()"))
        #expect(result.stdout.contains("%r1 = call i32 @puts(ptr getelementptr inbounds ([7 x i8], ptr @.str.0, i32 0, i32 0))"))
        #expect(result.stdout.contains("ret i32 0"))
    }

    @Test("Native compiler emits clean LLVM text")
    func nativeCompilerEmitsCleanLLVMText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerCleanLLVM.range")
        try """
        compilerLLVMText

        @main {
            return 7
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define i32 @main()"))
        #expect(result.stdout.contains("ret i32 7"))
        #expect(!result.stdout.contains("compilerCoreLLVM"))
        #expect(!result.stdout.contains("ast\\t"))
        #expect(!result.stdout.contains("identifier\\t"))
    }

    @Test("Native compiler preserves delimiter literals and unique global names")
    func nativeCompilerPreservesDelimiterLiteralsAndUniqueGlobalNames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerLiteralRecordsLLVM.range")
        try """
        compilerLLVMText

        function helperText(): String {
            return String("helper|~;@SEMICOLON@")
        }

        @main {
            let mainText: String(String("main"))
            print(value: helperText())
            print(value: mainText)
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains(#"[21 x i8] c"helper|~;@SEMICOLON@\00""#))
        #expect(result.stdout.contains(#"[5 x i8] c"main\00""#))
        #expect(!result.stdout.contains(#"c\""#))
        #expect(!result.stdout.contains("\\ndefine"))

        let globalNames = result.stdout.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("@.str."), let end = line.firstIndex(of: " ") else {
                return nil
            }
            return String(line[..<end])
        }
        #expect(!globalNames.isEmpty)
        #expect(Set(globalNames).count == globalNames.count)

        let llvm = directory.appendingPathComponent("LiteralRecords.ll")
        let executable = directory.appendingPathComponent("LiteralRecords")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-x", "ir", llvm.path, "-o", executable.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)

        let executableResult = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(executableResult.exitCode == 0)
        #expect(executableResult.stdout == "helper|~;@SEMICOLON@\nmain\n")
        #expect(executableResult.stderr.isEmpty)
    }

    @Test("Native compiler fails closed for unresolved calls")
    func nativeCompilerFailsClosedForUnresolvedCalls() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerUnresolvedCallLLVM.range")
        try """
        compilerLLVMText

        @main {
            missingFunction()
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("compilerError\\tkind=unsupportedReachableLowering\\tplaceholderCount=1"))
        #expect(!result.stdout.contains("define i32 @main()"))
    }

    @Test("Native compiler preserves locals across nested else-if lowering")
    func nativeCompilerPreservesLocalsAcrossNestedElseIfLowering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerNestedElseIfLLVM.range")
        try """
        compilerLLVMText

        construct Box {
            let value: Int
            let flag: Bool
        }

        function readBox(block: Box): Int {
            state current: Box(Box(value: 0, flag: false))
            current: block
            state result: Int(0)
            result: current.value
            if block.flag {
                result: block.value
            } else if block.value > 0 {
                result: 2
            }
            return result
        }

        function returningElse(flag: Bool): String {
            state value: String("initial")
            if flag {
                value: String("then")
            } else {
                return String("else")
            }
            return value
        }

        function returningElseIf(value: Int): Int {
            if value == 1 {
                return 1
            } else if value == 2 {
                return 2
            } else if value == 3 {
                return 3
            }
            return 0
        }

        function nestedMutationBeforeReturn(value: Int): String {
            state name: String("")
            if value > 0 {
                if value == 1 {
                    name: String("one")
                }
                return name
            }
            return name
        }

        @main {
            returningElse(flag: false)
            returningElseIf(value: 3)
            nestedMutationBeforeReturn(value: 1)
            return readBox(block: Box(value: 1, flag: false))
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(!result.stdout.contains("compilerError\\t"))
        #expect(result.stdout.contains("define i32 @readBox(ptr %block)"))
        #expect(result.stdout.contains("define i32 @returningElseIf(i32 %value)"))
        #expect(result.stdout.contains("define ptr @nestedMutationBeforeReturn(i32 %value)"))
        #expect(result.stdout.components(separatedBy: "icmp eq i32").count >= 4)
        #expect(result.stdout.contains("icmp sgt i32"))
        #expect(result.stdout.contains("phi i32"))
        #expect(result.stdout.contains("ret i32"))

        let llvm = directory.appendingPathComponent("NestedElseIf.ll")
        let object = directory.appendingPathComponent("NestedElseIf.o")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-c", "-x", "ir", llvm.path, "-o", object.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)
    }

    @Test("Native compiler lowers default pointer return as null")
    func nativeCompilerLowersDefaultPointerReturnAsNull() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerDefaultPointerReturnLLVM.range")
        try """
        compilerLLVMText

        function emptyString(): String {
        }

        @main {
            emptyString()
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define ptr @emptyString()"))
        #expect(result.stdout.contains("ret ptr null"))
        #expect(!result.stdout.contains("ret ptr 0"))
    }

    @Test("Native compiler lowers construct initializer as value placeholder")
    func nativeCompilerLowersConstructInitializerAsValuePlaceholder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerConstructInitializerLLVM.range")
        try """
        compilerLLVMText

        construct Box {
            let value: Int
        }

        function makeBox(): Box {
            return Box(value: 1)
        }

        @main {
            makeBox()
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define ptr @makeBox()"))
        #expect(result.stdout.contains("declare ptr @rangeConstructCreate(ptr)"))
        #expect(result.stdout.contains("declare ptr @rangeConstructSetInt(ptr, ptr, i32)"))
        #expect(result.stdout.contains("call ptr @rangeConstructCreate(ptr getelementptr inbounds"))
        #expect(result.stdout.contains("call ptr @rangeConstructSetInt(ptr"))
        #expect(!result.stdout.contains("ret ptr null"))
        #expect(!result.stdout.contains("call i32 @Box"))
    }

    @Test("Native compiler does not lower String member character as free function")
    func nativeCompilerDoesNotLowerStringMemberCharacterAsFreeFunction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerStringMemberCharacterLLVM.range")
        try """
        compilerLLVMText

        function sameFirst(left: String, right: String): Bool {
            return left.character(index: 0) == right.character(index: 0)
        }

        @main {
            if sameFirst(left: String("a"), right: String("a")) {
                return 0
            }
            return 1
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(!result.stdout.contains("@character"))
    }

    @Test("Native compiler harmonizes pointer comparison fallbacks")
    func nativeCompilerHarmonizesPointerComparisonFallbacks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerPointerComparisonFallback.range")
        try """
        compilerLLVMText

        @main {
            if missingValue != String("") {
                return 1
            }
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("call i32 @stringEqual(ptr null, ptr getelementptr inbounds"))
        #expect(result.stdout.contains("icmp eq i32"))
        #expect(!result.stdout.contains("icmp ne ptr null, getelementptr inbounds"))
        #expect(!result.stdout.contains("icmp ne i32 0, null"))
    }

    @Test("Native compiler lowers direct returned call through AST")
    func nativeCompilerLowersDirectReturnedCallThroughAST() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerReturnedCallLLVM.range")
        try """
        compilerLLVMText

        function makeValue(value: Int): Int {
            return value
        }

        @main {
            return makeValue(7)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define i32 @makeValue(i32 %value)"))
        #expect(result.stdout.contains("ret i32 %value"))
        #expect(result.stdout.contains("%r0 = call i32 @makeValue(i32 7)"))
        #expect(result.stdout.contains("ret i32 %r0"))
    }

    @Test("Native compiler lowers the shared TextBuffer ABI")
    func nativeCompilerLowersSharedTextBufferABI() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerTextBufferLLVM.range")
        try """
        compilerLLVMText

        function buildText(): String {
            let buffer: TextBuffer(textBufferCreate(capacity: 2))
            textBufferAppend(buffer: buffer, text: String("range"))
            textBufferAppendInt(buffer: buffer, value: 56)
            let text: String(textBufferMaterialize(buffer: buffer))
            textBufferDestroy(buffer: buffer)
            return text
        }

        @main {
            if buildText() == String("range56") {
                return 0
            }
            return 1
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("declare ptr @textBufferCreate(i32)"))
        #expect(result.stdout.contains("declare i32 @textBufferAppend(ptr, ptr)"))
        #expect(result.stdout.contains("declare i32 @textBufferAppendInt(ptr, i32)"))
        #expect(result.stdout.contains("declare ptr @textBufferMaterialize(ptr)"))
        #expect(result.stdout.contains("declare i32 @textBufferDestroy(ptr)"))
        #expect(result.stdout.contains("call ptr @textBufferCreate(i32 2)"))
        #expect(result.stdout.contains("call i32 @textBufferAppend(ptr"))
        #expect(result.stdout.contains("call i32 @textBufferAppendInt(ptr"))
        #expect(result.stdout.contains("call ptr @textBufferMaterialize(ptr"))
        #expect(result.stdout.contains("call i32 @textBufferDestroy(ptr"))
    }

    @Test("Native compiler lowers the shared String search ABI")
    func nativeCompilerLowersSharedStringSearchABI() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerStringSearchLLVM.range")
        try """
        compilerLLVMText

        function firstSeparator(source: String): Int {
            return stringFindFirstOf(source: source, start: 0, characters: String("|~"))
        }

        @main {
            return firstSeparator(source: String("range|compiler"))
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("declare i32 @stringFindFirstOf(ptr, i32, ptr)"))
        #expect(result.stdout.contains("call i32 @stringFindFirstOf(ptr"))
        #expect(result.stdout.contains("define i32 @firstSeparator(ptr %source)"))
    }

    @Test("Native compiler lowers helper branch return type")
    func nativeCompilerLowersHelperBranchReturnType() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerHelperBranchReturnLLVM.range")
        try """
        compilerLLVMText

        function chooseFlag(value: Bool): Bool {
            if value {
                return value
            }
            return value
        }

        @main {
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define i1 @chooseFlag(i1 %value)"))
        #expect(result.stdout.contains("ret i1 %value"))
        #expect(!result.stdout.contains("ret i32 %value"))
    }

    @Test("Native compiler lowers non-returning helper branch mutation")
    func nativeCompilerLowersNonReturningHelperBranchMutation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerHelperBranchMutationLLVM.range")
        try """
        compilerLLVMText

        function choose(value: Int): Int {
            let mutable: Int(1)
            if value != 0 {
                mutable: value + 1
            }
            return mutable
        }

        @main {
            return choose(2)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("%r0 = icmp ne i32 %value, 0"))
        #expect(result.stdout.contains("%r1 = add i32 %value, 1"))
        #expect(result.stdout.contains("%r2 = phi i32 [1, %entry], [%r1, %if0]"))
        #expect(result.stdout.contains("ret i32 %r2"))
        #expect(!result.stdout.contains("ret i32 1"))
    }

    @Test("Native compiler lowers non-returning helper if else mutation")
    func nativeCompilerLowersNonReturningHelperIfElseMutation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerHelperIfElseMutationLLVM.range")
        try """
        compilerLLVMText

        function choose(value: Int): Int {
            let mutable: Int(1)
            if value != 0 {
                mutable: value + 1
            } else {
                mutable: value - 1
            }
            return mutable
        }

        @main {
            return choose(2)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("%r0 = icmp ne i32 %value, 0"))
        #expect(result.stdout.contains("%r1 = add i32 %value, 1"))
        #expect(result.stdout.contains("%r2 = sub i32 %value, 1"))
        #expect(result.stdout.contains("%r3 = phi i32 [%r1, %if0], [%r2, %else0]"))
        #expect(result.stdout.contains("ret i32 %r3"))
        #expect(!result.stdout.contains("ret i32 1"))
    }

    @Test("Native compiler lowers multiple string states through no-else branch")
    func nativeCompilerLowersMultipleStringStatesThroughNoElseBranch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerHelperBranchStringStateLLVM.range")
        try """
        compilerCoreLLVM

        function collect(flag: Bool): String {
            state rendered: String("")
            state records: String("")
            if flag {
                rendered: "\\(rendered)x"
                records: "\\(records)y"
            }
            return "\\(rendered)\\(records)"
        }

        @main {
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define ptr @collect(i1 %flag)"))
        #expect(result.stdout.contains("%r6 = phi ptr [getelementptr inbounds ([1 x i8], ptr @.str.0, i32 0, i32 0), %entry], [%r3, %if0]"))
        #expect(result.stdout.contains("%r7 = phi ptr [getelementptr inbounds ([1 x i8], ptr @.str.1, i32 0, i32 0), %entry], [%r5, %if0]"))
        #expect(result.stdout.contains("%r8 = call ptr @stringConcat(ptr %r6, ptr %r7)"))
        #expect(result.stdout.contains("ret ptr %r8"))
    }

    @Test("Native compiler emits combined source-set LLVM report")
    func nativeCompilerEmitsCombinedSourceSetLLVMReport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerSourceSetLLVM.range")
        try """
        compilerSourceSetLLVM
        compilerSourceFile\\tHelper.range
        function choose(value: Int): Int {
            return adjust(value)
        }

        function adjust(value: Int): Int {
            return value + 1
        }
        compilerSourceFile\\tMain.range
        @main {
            return choose(7)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("sourceSetLLVM\\tprogram"))
        #expect(result.stdout.contains("sourceFileLLVM\\tindex=0\\tpath=Helper.range\\thasMainBlock=false"))
        #expect(result.stdout.contains("sourceFileLLVM\\tindex=1\\tpath=Main.range\\thasMainBlock=true"))
        #expect(result.stdout.contains("sourceSetLLVMProgram\\thasMainBlock=true"))
        #expect(result.stdout.contains("sourceFileLLVMCount\\t2"))
        #expect(!result.stdout.contains("sourceSetLLVMProgramText"))
        #expect(!result.stdout.contains("define i32 @choose(i32 %value)"))
    }

    @Test("Native compiler emits clean combined source-set LLVM text")
    func nativeCompilerEmitsCleanCombinedSourceSetLLVMText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerSourceSetLLVMText.range")
        try """
        compilerSourceSetLLVMText
        compilerSourceFile\\tHelper.range
        function choose(value: Int): Int {
            return adjust(value)
        }

        function adjust(value: Int): Int {
            return value + 1
        }
        compilerSourceFile\\tMain.range
        @main {
            return choose(2)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("define i32 @choose(i32 %value)"))
        #expect(result.stdout.contains("define i32 @adjust(i32 %value)"))
        #expect(result.stdout.contains("define i32 @main()"))
        #expect(result.stdout.contains("%r0 = call i32 @choose(i32 2)"))
        #expect(!result.stdout.contains("sourceSetLLVM\\tprogram"))
        #expect(!result.stdout.contains("sourceSetLLVMProgramText"))
        #expect(!result.stdout.contains("ast\\t"))
    }

    @Test("Native compiler emits compiler-core LLVM from AST")
    func nativeCompilerEmitsCompilerCoreLLVMFromAST() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerCoreLLVM.range")
        try """
        compilerCoreLLVM

        function makeValue(value: Int): Int {
            return value
        }

        function combine(left: Int, right: Int): Int {
            return left + right
        }

        function isDifferent(left: Int, right: Int): Bool {
            return left != right
        }

        function keepFlag(value: Bool): Bool {
            return value
        }

        @main {
            let first: Int(1)
            let second: Int(2)
            let different: Bool(first != second)
            let declaredDifferent: Bool(isDifferent(first, second))
            let kept: Bool(keepFlag(declaredDifferent))
            let same: Bool(declaredDifferent == kept)
            let inverted: Bool(!declaredDifferent)
            let negative: Int(-first)
            makeValue(second)
            let mutable: Int(1)
            mutable: first + second
            let reassigned: Int(mutable + 5)
            let count: Int(commandLineArgumentCount())
            let made: Int(makeValue(first))
            let combined: Int(combine(first, second + makeValue(3)))
            let third: Int(first + second * 3)
            let loopIndex: Int(0)
            let loopTotal: Int(10)
            while loopIndex < 2 {
                loopIndex: loopIndex + 1
                loopTotal: loopTotal + loopIndex
            }
            while same {
                makeValue(first)
                continue
            }
            while different {
                makeValue(second)
                break
            }
            if different {
                let branchBase: Int(first + 8)
                branchBase: branchBase + 1
                return branchBase
            }
            if same {
                let secondBranch: Int(second + 10)
                return secondBranch
            } else {
                let fallbackBranch: Int(third + 4)
                return fallbackBranch
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("compilerCoreLLVM\\tmain"))
        #expect(result.stdout.contains("define i32 @makeValue(i32 %value)"))
        #expect(result.stdout.contains("define i32 @main()"))
        #expect(result.stdout.contains("%r0 = icmp ne i32 1, 2"))
        #expect(result.stdout.contains("%r1 = call i1 @isDifferent(i32 1, i32 2)"))
        #expect(result.stdout.contains("%r2 = call i1 @keepFlag(i1 %r1)"))
        #expect(result.stdout.contains("%r3 = icmp eq i1 %r1, %r2"))
        #expect(result.stdout.contains("%r4 = xor i1 %r1, true"))
        #expect(result.stdout.contains("%r5 = sub i32 0, 1"))
        #expect(result.stdout.contains("%r6 = call i32 @makeValue(i32 2)"))
        #expect(result.stdout.contains("%r7 = add i32 1, 2"))
        #expect(result.stdout.contains("%r8 = add i32 %r7, 5"))
        #expect(result.stdout.contains("%r9 = call i32 @commandLineArgumentCount()"))
        #expect(result.stdout.contains("%r10 = call i32 @makeValue(i32 1)"))
        #expect(result.stdout.contains("%r11 = call i32 @makeValue(i32 3)"))
        #expect(result.stdout.contains("%r12 = add i32 2, %r11"))
        #expect(result.stdout.contains("%r13 = call i32 @combine(i32 1, i32 %r12)"))
        #expect(result.stdout.contains("%r14 = mul i32 2, 3"))
        #expect(result.stdout.contains("%r15 = add i32 1, %r14"))
        #expect(result.stdout.contains("phi i32 [0, %entry], [%"))
        #expect(result.stdout.contains("phi i32 [10, %entry], [%"))
        #expect(result.stdout.contains("icmp slt i32 %"))
        #expect(result.stdout.contains("add i32 %"))
        #expect(result.stdout.contains("call i32 @makeValue(i32 %"))
        #expect(result.stdout.contains("ret i32 %"))
        #expect(result.stdout.contains("br label %while0"))
        #expect(result.stdout.contains("while0:\n"))
        #expect(result.stdout.contains("label %whileBody0, label %afterWhile0"))
        #expect(result.stdout.contains("whileBody0:\n"))
        #expect(result.stdout.contains("br label %while0"))
        #expect(result.stdout.contains("afterWhile0:\n  br label %while1"))
        #expect(result.stdout.contains("label %whileBody1, label %afterWhile1"))
        #expect(result.stdout.contains("whileBody1:\n"))
        #expect(result.stdout.contains("afterWhile1:\n  br label %while2"))
        #expect(result.stdout.contains("label %whileBody2, label %afterWhile2"))
        #expect(result.stdout.contains("whileBody2:\n"))
        #expect(result.stdout.contains("afterWhile2:\n  br i1 %"))
        #expect(result.stdout.contains("if3:\n"))
        #expect(result.stdout.contains("after3:\n  br i1 %"))
        #expect(result.stdout.contains("if4:\n"))
        #expect(result.stdout.contains("else4:\n"))
        #expect(!result.stdout.contains("loweredStatements="))
        #expect(!result.stdout.contains("llvm\\tmain"))
    }

    @Test("Native compiler lowers string state through while phi")
    func nativeCompilerLowersStringStateThroughWhilePhi() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("StringStateLoop.range")
        try """
        compilerCoreLLVM

        function appendOnce(source: String): String {
            state output: String("")
            state records: String("")
            state sourceIndex: Int(0)
            let recordsLength: Int(stringLength(value: source))

            while sourceIndex < recordsLength {
                output: "\\(output)x"
                records: "\\(records)y"
                sourceIndex: sourceIndex + 1
            }

            return "\\(output)\\(records)"
        }

        @main {
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define ptr @appendOnce(ptr %source)"))
        #expect(result.stdout.contains("phi ptr [getelementptr inbounds ([1 x i8]"))
        #expect(result.stdout.contains("call ptr @stringConcat(ptr %"))
        #expect(result.stdout.contains("ret ptr %"))
        let hasSelfReferentialEmptyStringPhi = result.stdout.split(separator: "\n").contains { line in
            guard line.contains(" = phi ptr "),
                let resultName = line.split(separator: "=").first?.trimmingCharacters(in: .whitespaces)
            else {
                return false
            }
            return line.contains("phi ptr [getelementptr inbounds ([1 x i8]") && line.contains("[\(resultName), %")
        }
        #expect(hasSelfReferentialEmptyStringPhi == false)
    }

    @Test("Native compiler lowers nested construct member comparisons as integers")
    func nativeCompilerLowersNestedConstructMemberComparisonsAsIntegers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("NestedConstructMembers.range")
        try """
        compilerCoreLLVM

        construct Cursor {
            let source: String
            let index: Int
        }

        construct State {
            let cursor: Cursor
            let end: Int
            let keepScanning: Bool
        }

        function check(parseState: State): Int {
            state scanState: State(parseState)
            while scanState.keepScanning && scanState.cursor.index < scanState.end {
                return 1
            }
            return 0
        }

        @main {
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define i32 @check(ptr %parseState)"))
        #expect(result.stdout.contains("call i1 @rangeConstructGetBool(ptr %"))
        #expect(result.stdout.contains("call ptr @rangeConstructGetPtr(ptr %"))
        #expect(result.stdout.contains("call i32 @rangeConstructGetInt(ptr %"))
        #expect(result.stdout.contains("icmp slt i32 %"))
        #expect(!result.stdout.contains("icmp slt ptr"))
    }

    @Test("Native compiler preserves binary expression records for boolean or")
    func nativeCompilerPreservesBinaryExpressionRecordsForBooleanOr() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("StringKindOr.range")
        try """
        compilerCoreLLVM

        construct Token {
            let kind: String
        }

        function check(token: Token): Bool {
            return token.kind == String("identifier") || token.kind == String("keyword")
        }

        @main {
            return 0
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define i1 @check(ptr %token)"))
        #expect(result.stdout.contains("call i32 @stringEqual(ptr %"))
        #expect(result.stdout.contains("or i1 %"))
        #expect(!result.stdout.contains("add i1 %"))
        #expect(!result.stdout.contains(", null"))
    }

    @Test("Native compiler parses function declarations")
    func nativeCompilerParsesFunctionDeclarations() throws {
        let source = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range")
        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreASTSummary"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreFunctionDeclarationSummary"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVM"))
        #expect(result.stdout.contains("ast\\tfunction\\tname=compilerCoreMainLLVM"))
    }

    @Test("Emit example check rejects missing directories")
    func emitExampleCheckRejectsMissingDirectories() throws {
        let missing = try repositoryRoot()
            .appendingPathComponent(
                "RangePlayground/Examples/LLVM/MissingDirectory",
                isDirectory: true
            )

        let result = try runRangeScript(arguments: ["check-llvm-examples", missing.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Missing LLVM examples directory"))
    }

    @Test("Emit example check rejects empty directories")
    func emitExampleCheckRejectsEmptyDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runRangeScript(arguments: ["check-llvm-examples", directory.path])

        #expect(result.timedOut == false)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("No LLVM examples found"))
    }
}

private func runRangeScript(arguments: [String], timeout: TimeInterval = 10) throws -> ScriptResult {
    let process = Process()
    process.executableURL = try repositoryRoot()
        .appendingPathComponent("scripts/range")
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    let prebuiltRangeCompiler = try repositoryRoot()
        .appendingPathComponent("RangeCompiler/.build/debug/range")
    if FileManager.default.isExecutableFile(atPath: prebuiltRangeCompiler.path) {
        environment["RANGE_BIN"] = prebuiltRangeCompiler.path
    }
    process.environment = environment

    let captureDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: captureDirectory) }

    let stdoutURL = captureDirectory.appendingPathComponent("stdout.txt")
    let stderrURL = captureDirectory.appendingPathComponent("stderr.txt")
    _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle

    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    let timedOut = process.isRunning
    if timedOut {
        process.terminate()
    }
    process.waitUntilExit()
    try? stdoutHandle.close()
    try? stderrHandle.close()

    return ScriptResult(
        exitCode: process.terminationStatus,
        stdout: (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? "",
        stderr: (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? "",
        timedOut: timedOut
    )
}

private func runCapturedProcess(executable: String, arguments: [String]) throws -> ScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    return ScriptResult(
        exitCode: process.terminationStatus,
        stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        timedOut: false
    )
}

private func temporaryManifest(contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = directory.appendingPathComponent("manifest.tsv")
    try contents.write(to: manifest, atomically: true, encoding: .utf8)
    return manifest
}

private func rangeExampleNames(in directory: URL) throws -> [String] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw RangeScriptTestError.missingDirectory(directory.path)
    }

    var names: [String] = []
    while let url = enumerator.nextObject() as? URL {
        let isRegularFile =
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegularFile, url.pathExtension == "range" else {
            continue
        }
        names.append(url.lastPathComponent)
    }
    return names.sorted()
}

private func runManifestNames(in manifest: URL) throws -> [String] {
    let text = try String(contentsOf: manifest, encoding: .utf8)
    return text.split(separator: "\n")
        .compactMap { line -> String? in
            guard !line.isEmpty, !line.hasPrefix("#") else {
                return nil
            }
            return line.split(separator: "\t", omittingEmptySubsequences: false)
                .first
                .map(String.init)
        }
        .sorted()
}

private func nativeLexerTokens(from stdout: String) -> [LexerTokenSnapshot] {
    stdout
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t")
        .split(separator: "\n")
        .compactMap { line -> LexerTokenSnapshot? in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3, Int(columns[0]) != nil else {
                return nil
            }
            return LexerTokenSnapshot(kind: String(columns[1]), source: String(columns[2]))
        }
}

private func nativeCompilerLexerTokens(for source: URL) throws -> [LexerTokenSnapshot] {
    let compiler = try repositoryRoot()
        .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
    let result = try runRangeScript(
        arguments: ["run", compiler.path, "--", source.path],
        timeout: 120
    )

    if result.timedOut || result.exitCode != 0 || !result.stderr.isEmpty {
        throw RangeScriptTestError.nativeLexerFailed(source.path, result.stderr)
    }

    return nativeLexerTokens(from: result.stdout)
}

private func swiftBootstrapLexerTokens(for source: URL) throws -> [LexerTokenSnapshot] {
    let text = try String(contentsOf: source, encoding: .utf8)
    let result = RangeAuthoredLexer().tokenize(source: text, foreignBodies: [])
    switch result {
    case .success(let tokens):
        return tokens.compactMap { token -> LexerTokenSnapshot? in
            let kind = swiftBootstrapLexerKindName(token.kind)
            guard kind != "eof" else {
                return nil
            }
            return LexerTokenSnapshot(kind: kind, source: token.source)
        }
    case .failure(let error):
        throw RangeScriptTestError.swiftLexerFailed(error.message)
    }
}

private func swiftBootstrapLexerKindName(_ kind: RangeAuthoredTokenKind) -> String {
    switch kind {
    case .hash:
        return "hash"
    case .identifier:
        return "identifier"
    case .foreignBody:
        return "foreignBody"
    case .stringLiteral:
        return "stringLiteral"
    case .integer:
        return "integer"
    case .double:
        return "double"
    case .keyword:
        return "keyword"
    case .macroAttribute:
        return "macroAttribute"
    case .leftBrace:
        return "leftBrace"
    case .rightBrace:
        return "rightBrace"
    case .leftParen:
        return "leftParen"
    case .rightParen:
        return "rightParen"
    case .leftBracket:
        return "leftBracket"
    case .rightBracket:
        return "rightBracket"
    case .asterisk:
        return "asterisk"
    case .dot:
        return "dot"
    case .ellipsis:
        return "ellipsis"
    case .colon:
        return "colon"
    case .arrow:
        return "arrow"
    case .bang:
        return "bang"
    case .equal:
        return "equal"
    case .equalEqual:
        return "equalEqual"
    case .bangEqual:
        return "bangEqual"
    case .minus:
        return "minus"
    case .less:
        return "less"
    case .lessEqual:
        return "lessEqual"
    case .greater:
        return "greater"
    case .greaterEqual:
        return "greaterEqual"
    case .plus:
        return "plus"
    case .slash:
        return "slash"
    case .ampersand:
        return "ampersand"
    case .andAnd:
        return "andAnd"
    case .pipe:
        return "pipe"
    case .orOr:
        return "orOr"
    case .question:
        return "question"
    case .questionQuestion:
        return "questionQuestion"
    case .dollar:
        return "dollar"
    case .percent:
        return "percent"
    case .comma:
        return "comma"
    case .eof:
        return "eof"
    }
}

private func repositoryRoot() throws -> URL {
    var current = URL(fileURLWithPath: #filePath)
    while current.path != "/" {
        let script = current
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("range")
        let rangePackage = current
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: script.path),
            FileManager.default.fileExists(atPath: rangePackage.path)
        {
            return current
        }
        current.deleteLastPathComponent()
    }
    throw RangeScriptTestError.repositoryRootNotFound
}

private struct ScriptResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
}

private struct LexerTokenSnapshot: Equatable {
    var kind: String
    var source: String
}

private enum RangeScriptTestError: Error {
    case missingDirectory(String)
    case repositoryRootNotFound
    case nativeLexerFailed(String, String)
    case swiftLexerFailed(String)
}
