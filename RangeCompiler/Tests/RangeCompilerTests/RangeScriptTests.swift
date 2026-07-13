import CryptoKit
import Darwin
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

    @Test("Ordinary reachability discovery uses typed body edges only")
    func ordinaryReachabilityDiscoveryUsesTypedBodyEdgesOnly() throws {
        let root = try repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"),
            encoding: .utf8
        )
        guard let start = source.range(of: "function compilerReachableLLVMStateDiscoverFunction("),
              let end = source.range(of: "\nfunction compilerReachableLLVMStateEmitFunction(", range: start.upperBound..<source.endIndex) else {
            #expect(Bool(false))
            return
        }
        let discovery = String(source[start.lowerBound..<end.lowerBound])
        #expect(discovery.contains("compilerBodyArenaAppendFunctionEdges"))
        #expect(discovery.contains("compilerBodyMIRAppendFunctionEdges"))
        #expect(!discovery.contains("compilerCoreParseStatements"))
        #expect(!discovery.contains("compilerLegacyAppend"))
        #expect(!discovery.contains("parseCompilerExpression"))
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
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerBlockWithLocals(ptr %context, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerBlockWithControl(ptr %context, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLoweredBlockRenderedBlocks(ptr %block)"))
        #expect(llvmText.contains("call ptr @compilerCoreLLVMLoweredBlockRenderedBlocks(ptr"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectLinearRecordBlockWithRecord(ptr %context, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectLinearRecordBlockWithIf(ptr %context, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectIfStatementRecord(ptr %context, ptr %parsedBlock"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectIfStatementRecordWithElse(ptr %context"))
        #expect(llvmText.contains("define ptr @compilerCoreRenderedDirectIfElseStatementRecord(ptr %context"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerDirectIfStatementRecordWithAfter(ptr %context"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerLinearStatementRecord(ptr %context, ptr %statementRecord"))
        #expect(llvmText.contains("define ptr @compilerCoreLLVMLowerLinearStatementRecordReturn(ptr %context"))
        #expect(llvmText.contains("define ptr @compilerCoreRenderedDirectReturnBlock(ptr %context, ptr %parsedBlock"))
        #expect(llvmText.contains("define i1 @compilerCoreCanLowerLocalType(ptr %context, ptr %typeName)"))
        #expect(llvmText.contains("define i32 @main() {\nentry:\n  %r0 = call i32 @commandLineArgumentCount()"))
        #expect(llvmText.contains("br i1 %r1, label %if0, label %after0"))
        #expect(llvmText.contains("after0:\n"))
        #expect(llvmText.contains("call ptr @commandLineArgument(i32 0)"))
        #expect(llvmText.contains("call ptr @readFile(ptr"))
        #expect(llvmText.contains("call ptr @compileRangeNativeSource(ptr"))
        #expect(!llvmText.contains("define ptr @compilerCoreMainParsedBlock(ptr %program) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define ptr @parseCompilerStatementWithToken(ptr %program, ptr %cursor, ptr %maybeToken, i32 %bodyEnd) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define ptr @compilerCoreLLVMLowerBlockWithControl(ptr %context, ptr %parsedBlock, ptr %initialLocalValues, i32 %initialTemporaryIndex, ptr %expectedReturnType, ptr %initialBlockLabel, ptr %fallthroughLabel, i32 %initialBranchIndex) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define ptr @compilerCoreLLVMLowerLinearStatementRecord(ptr %context, ptr %statementRecord, ptr %localValues, i32 %temporaryIndex, ptr %expectedReturnType) {\nentry:\n  ret ptr null"))
        #expect(!llvmText.contains("define i32 @main() {\nentry:\n  ret i32 64\n}"))
        #expect(!llvmText.contains("add i1 %"))
        #expect(!llvmText.contains("stringEqual(ptr null"))
        #expect(!llvmText.contains("@character"))
        #expect(!llvmText.contains("@CompilerLLVMBasicBlock"))

        let smokeLLVMText = try String(contentsOf: smokeLLVM, encoding: .utf8)
        #expect(smokeLLVMText.contains("define i32 @main() {\nentry:"))
        #expect(smokeLLVMText.contains("%storage0 = alloca"))
        #expect(smokeLLVMText.contains("ret i32 %value"))
        #expect(!smokeLLVMText.contains("\\n"))

        let stage3LLVMText = try String(contentsOf: stage3Candidate, encoding: .utf8)
        #expect(stage3LLVMText.contains("define ptr @compileRangeNativeSource(ptr %source)"))
        #expect(stage3LLVMText.contains("define ptr @parseCompilerAssignmentStatement(ptr %token"))
        #expect(stage3LLVMText.contains("define ptr @compilerCoreRenderedDirectIfElseStatementRecord(ptr %context"))
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
        let mainSource = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Main.range")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try runTypedSyntaxFixture(
            source: "compilerSourceSetAST\ncompilerSourceFile\\tMain.range\n\(try String(contentsOf: mainSource, encoding: .utf8))",
            name: "MainSourceSetAST.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("sourceSetAST\\tprogram"))
        #expect(result.stdout.contains("sourceFileAST\\tindex=0\\tpath=Main.range\\thasMainBlock=true"))
        #expect(result.stdout.contains("sourceFileASTCount\\t1"))
    }

    @Test("Native compiler emits clean ordinary LLVM")
    func nativeCompilerEmitsCleanOrdinaryLLVM() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try runTypedSyntaxFixture(
            source: """
            @main {
                return 0
            }

            """,
            name: "OrdinaryMain.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(!result.stdout.contains("ast\\t"))
        #expect(!result.stdout.contains("compilerCoreLLVM\\t"))
        #expect(result.stdout.contains("declare i32 @puts(ptr)"))
        #expect(result.stdout.contains("define i32 @main()"))
        #expect(result.stdout.contains("ret i32 0"))
    }

    @Test("Native compiler lowers typed member applications through ordinary LLVM")
    func nativeCompilerLowersTypedMemberApplicationsThroughOrdinaryLLVM() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try runTypedSyntaxFixture(
            source: """
            @main {
                let source: String("range")
                let value: String(source.substring(start: 0, end: 1))
                if value.character(index: 0) == String("r") {
                    return 0
                }
                return 1
            }

            """,
            name: "OrdinaryMemberApplications.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("call ptr @stringSubstring(ptr"))
        #expect(result.stdout.contains("call ptr @stringCharacterAt(ptr"))
        #expect(!result.stdout.contains("@substring"))
        #expect(!result.stdout.contains("@character"))
        #expect(!result.stdout.contains("RANGE_LOWERING_PLACEHOLDER"))
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

    @Test("Native compiler lowers the shared IntBuffer ABI")
    func nativeCompilerLowersSharedIntBufferABI() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerIntBufferLLVM.range")
        try """
        compilerLLVMText

        function bufferedValue(): Int {
            let buffer: IntBuffer(intBufferCreate(capacity: 1))
            intBufferAppend(buffer: buffer, value: 7)
            intBufferAppend(buffer: buffer, value: 11)
            let count: Int(intBufferCount(buffer: buffer))
            let value: Int(intBufferElement(buffer: buffer, index: 1))
            intBufferDestroy(buffer: buffer)
            return count + value
        }

        @main {
            return bufferedValue()
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
        #expect(result.stdout.contains("declare ptr @intBufferCreate(i32)"))
        #expect(result.stdout.contains("declare i32 @intBufferAppend(ptr, i32)"))
        #expect(result.stdout.contains("declare i32 @intBufferCount(ptr)"))
        #expect(result.stdout.contains("declare i32 @intBufferElement(ptr, i32)"))
        #expect(result.stdout.contains("declare i32 @intBufferSet(ptr, i32, i32)"))
        #expect(result.stdout.contains("declare i32 @intBufferDestroy(ptr)"))
        #expect(result.stdout.contains("call ptr @intBufferCreate(i32 1)"))
        #expect(result.stdout.contains("call i32 @intBufferAppend(ptr"))
        #expect(result.stdout.contains("call i32 @intBufferCount(ptr"))
        #expect(result.stdout.contains("call i32 @intBufferElement(ptr"))
        #expect(result.stdout.contains("call i32 @intBufferDestroy(ptr"))
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

    @Test("Native compiler snapshots bundled source file identity and local offsets")
    func nativeCompilerSnapshotsBundledSourceIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerSourceIdentity.range")
        let sourceText = """
        compilerSourceIdentity
        compilerSourceFile\\tHelper.range
        function choose(value: Int): Int {
            return value + 1
        }
        compilerSourceFile\\tMain.range
        @main {
            return choose(2)
        }

        """
        try sourceText.write(to: source, atomically: true, encoding: .utf8)

        let helperPathRange = try #require(sourceText.range(of: "Helper.range"))
        let mainPathRange = try #require(sourceText.range(of: "Main.range"))
        let secondMarkerRange = try #require(
            sourceText.range(of: "compilerSourceFile\\tMain.range")
        )
        let helperPathStart = sourceText[..<helperPathRange.lowerBound].utf8.count
        let helperPathEnd = sourceText[..<helperPathRange.upperBound].utf8.count
        let helperContentStart = helperPathEnd + 1
        let helperContentEnd = sourceText[..<secondMarkerRange.lowerBound].utf8.count
        let mainPathStart = sourceText[..<mainPathRange.lowerBound].utf8.count
        let mainPathEnd = sourceText[..<mainPathRange.upperBound].utf8.count
        let mainContentStart = mainPathEnd + 1
        let mainContentEnd = sourceText.utf8.count

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("sourceIdentity\tfileCount=2\n"))
        #expect(
            result.stdout.contains(
                "sourceFile\tid=0\trole=project\tpath=Helper.range\tpathStart=\(helperPathStart)\tpathEnd=\(helperPathEnd)\tcontentStart=\(helperContentStart)\tcontentEnd=\(helperContentEnd)\n"
            )
        )
        #expect(
            result.stdout.contains(
                "sourceMap\tglobal=\(helperContentStart)\tfileID=0\tlocal=0\n"
            )
        )
        #expect(
            result.stdout.contains(
                "sourceFile\tid=1\trole=project\tpath=Main.range\tpathStart=\(mainPathStart)\tpathEnd=\(mainPathEnd)\tcontentStart=\(mainContentStart)\tcontentEnd=\(mainContentEnd)\n"
            )
        )
        #expect(
            result.stdout.contains(
                "sourceMap\tglobal=\(mainContentStart)\tfileID=1\tlocal=0\n"
            )
        )
    }

    @Test("Native compiler assigns FileID zero to an ordinary source")
    func nativeCompilerSnapshotsOrdinarySourceIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("CompilerOrdinarySourceIdentity.range")
        let sourceText = """
        compilerSourceIdentity
        function value(): Int {
            return 7
        }

        """
        try sourceText.write(to: source, atomically: true, encoding: .utf8)

        let compiler = try repositoryRoot()
            .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let result = try runRangeScript(
            arguments: ["run", compiler.path, "--", source.path],
            timeout: 120
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("sourceIdentity\tfileCount=1\n"))
        #expect(
            result.stdout.contains(
                "sourceFile\tid=0\trole=project\tpath=\tpathStart=0\tpathEnd=0\tcontentStart=0\tcontentEnd=\(sourceText.utf8.count)\n"
            )
        )
        #expect(result.stdout.contains("sourceMap\tglobal=0\tfileID=0\tlocal=0\n"))
    }

    @Test("Native compiler snapshots dense typed Pair syntax with structural fingerprints")
    func nativeCompilerSnapshotsDenseTypedPairSyntax() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let baseSource = """
        compilerTypedSyntax
        compilerSourceFile\\tPair.range
        construct Pair {
            let left: Int
            let right: Int
        }

        function sum(pair: Pair): Int {
            return pair.left + pair.right
        }
        compilerSourceFile\\tMain.range
        @main {
            let pair: Pair(left: 3, right: 4)
            return sum(pair: pair)
        }

        """
        let bodyEditSource = baseSource.replacingOccurrences(
            of: "return pair.left + pair.right",
            with: "return pair.right + pair.left"
        )
        let signatureEditSource = baseSource.replacingOccurrences(
            of: "function sum(pair: Pair): Int",
            with: "function sum(pair: Int): Int"
        )

        let baseResult = try runTypedSyntaxFixture(
            source: baseSource,
            name: "TypedPairBase.range",
            directory: directory
        )
        let bodyEditResult = try runTypedSyntaxFixture(
            source: bodyEditSource,
            name: "TypedPairBodyEdit.range",
            directory: directory
        )
        let signatureEditResult = try runTypedSyntaxFixture(
            source: signatureEditSource,
            name: "TypedPairSignatureEdit.range",
            directory: directory
        )

        #expect(baseResult.timedOut == false)
        #expect(baseResult.exitCode == 0)
        #expect(baseResult.stderr.isEmpty)
        #expect(
            baseResult.stdout.hasPrefix(
                "typedSyntax\tvalid=true\tidentityScope=pathStable,pathlessSnapshotLocal\tfileCount=2\tsyntaxCount=25\tdeclarationCount=2\tmemberCount=2\tfunctionCount=1\tparameterCount=1\tbodyNodeCount=20\tbodyEdgeCount=19\n"
            )
        )
        #expect(baseResult.stdout.contains("declaration\trow=0\tsyntaxID=0\tfileID=0\tkind=construct"))
        #expect(baseResult.stdout.contains("declaration\trow=1\tsyntaxID=3\tfileID=0\tkind=function"))
        #expect(baseResult.stdout.contains("member\trow=0\tsyntaxID=1\tfileID=0\tparentSyntaxID=0\tordinal=0"))
        #expect(baseResult.stdout.contains("parameter\trow=0\tsyntaxID=4\tfileID=0\tfunctionID=0\tordinal=0"))
        #expect(baseResult.stdout.contains("syntax\tid=9\tkind=addition\tfacetRow=4"))
        #expect(baseResult.stdout.contains("syntax\tid=11\tkind=mainAnnotation\tfacetRow=6"))
        #expect(baseResult.stdout.contains("syntax\tid=14\tkind=application\tfacetRow=9"))
        #expect(baseResult.stdout.contains("syntax\tid=19\tkind=local\tfacetRow=14"))
        #expect(baseResult.stdout.contains("typedTable\tname=bodyNode\tversion=1\tcolumns=11\trows=20"))
        #expect(baseResult.stdout.contains("typedTable\tname=bodyEdge\tversion=1\tcolumns=4\trows=19"))

        let baseFingerprint = try #require(
            typedSyntaxDeclarationFingerprint(in: baseResult.stdout, name: "sum")
        )
        let bodyEditFingerprint = try #require(
            typedSyntaxDeclarationFingerprint(in: bodyEditResult.stdout, name: "sum")
        )
        let signatureEditFingerprint = try #require(
            typedSyntaxDeclarationFingerprint(in: signatureEditResult.stdout, name: "sum")
        )
        #expect(bodyEditResult.stdout != baseResult.stdout)
        #expect(bodyEditFingerprint == baseFingerprint)
        #expect(signatureEditFingerprint != baseFingerprint)
    }

    @Test("Typed declaration fingerprint survives unrelated declaration reorder")
    func typedDeclarationFingerprintSurvivesUnrelatedDeclarationReorder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let constructSource = """
        construct Pair {
            let left: Int
            let right: Int
        }

        """
        let helperSource = """
        function helper(): Int {
            return 1
        }

        """
        let sumSource = """
        function sum(pair: Pair): Int {
            return pair.left + pair.right
        }

        """
        let helperFirstSource = """
        compilerTypedSyntax
        compilerSourceFile\\tPair.range
        \(constructSource)\(helperSource)\(sumSource)
        """
        let helperLastSource = """
        compilerTypedSyntax
        compilerSourceFile\\tPair.range
        \(constructSource)\(sumSource)\(helperSource)
        """

        let helperFirstResult = try runTypedSyntaxFixture(
            source: helperFirstSource,
            name: "TypedPairHelperFirst.range",
            directory: directory
        )
        let helperLastResult = try runTypedSyntaxFixture(
            source: helperLastSource,
            name: "TypedPairHelperLast.range",
            directory: directory
        )
        #expect(helperFirstResult.exitCode == 0)
        #expect(helperLastResult.exitCode == 0)
        #expect(helperFirstResult.stderr.isEmpty)
        #expect(helperLastResult.stderr.isEmpty)
        #expect(helperFirstResult.stdout != helperLastResult.stdout)
        #expect(
            typedSyntaxDeclarationFingerprint(in: helperFirstResult.stdout, name: "sum")
                == typedSyntaxDeclarationFingerprint(in: helperLastResult.stdout, name: "sum")
        )
    }

    @Test("Typed syntax rejects duplicate declaration fingerprints")
    func typedSyntaxRejectsDuplicateDeclarationFingerprints() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerTypedSyntax
            compilerSourceFile\\tDuplicate.range
            function value(): Int {
                return 1
            }

            function value(): Int {
                return 2
            }

            """,
            name: "TypedDuplicateDeclarations.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidTypedSyntaxSnapshot\n\n")
    }

    @Test("Typed body subset fails closed without a legacy-record fallback")
    func typedBodySubsetFailsClosedWithoutLegacyRecordFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerTypedSyntax
            compilerSourceFile\\tUnsupportedBody.range
            function difference(left: Int, right: Int): Int {
                return left - right
            }

            """,
            name: "TypedUnsupportedBody.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidTypedSyntaxSnapshot\n\n")
    }

    @Test("Native compiler plots Pair graph delta from live typed tables")
    func nativeCompilerPlotsPairGraphDeltaFromLiveTypedTables() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerPlotter
            compilerSourceFile\\tPair.range
            construct Pair {
                let left: Int
                let right: Int
            }

            function sum(pair: Pair): Int {
                return pair.left + pair.right
            }
            compilerSourceFile\\tMain.range
            @main {
                let pair: Pair(left: 3, right: 4)
                return sum(pair: pair)
            }

            """,
            name: "PairGraphDelta.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("graphDelta\tvalid=true\tnodeCount=25\tfactCount=22\n"))
        #expect(result.stdout.contains("typedTable\tname=graphNode\tversion=1\tcolumns=8\trows=25"))
        #expect(result.stdout.contains("typedTable\tname=graphFact\tversion=1\tcolumns=5\trows=22"))
        #expect(result.stdout.contains("graphFact\trow=0\tvalues=1,0,1,10,0"))
        #expect(result.stdout.contains("graphFact\trow=3\tvalues=1,3,4,11,0"))
        #expect(result.stdout.contains("graphFact\trow=9\tvalues=2,11,12,12,0"))
        #expect(result.stdout.contains("graphFact\trow=21\tvalues=1,24,21,3,0"))
    }

    @Test("Native compiler resolves Pair semantics from the graph delta")
    func nativeCompilerResolvesPairSemanticsFromGraphDelta() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerSemantics
            compilerSourceFile\\tPair.range
            construct Pair {
                let left: Int
                let right: Int
            }

            function sum(pair: Pair): Int {
                return pair.left + pair.right
            }
            compilerSourceFile\\tMain.range
            @main {
                let pair: Pair(left: 3, right: 4)
                return sum(pair: pair)
            }

            """,
            name: "PairSemantics.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("semanticGraph\tvalid=true\tresolutionCount=12\ttypeCount=25\teffectCount=1\taccessEffectCount=0\n"))
        #expect(result.stdout.contains("semanticResolution\trow=10\tvalues=22,19,3"))
        #expect(result.stdout.contains("semanticResolution\trow=11\tvalues=23,4,7"))
        #expect(result.stdout.contains("semanticType\trow=19\tvalues=19,2,0"))
        #expect(result.stdout.contains("semanticEffect\trow=0\tvalues=3,4,1,0,0"))
    }

    @Test("Native compiler proves fixed-layout Pair memory decisions")
    func nativeCompilerProvesFixedLayoutPairMemoryDecisions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            compilerSourceFile\\tPair.range
            construct Pair {
                let left: Int
                let right: Int
            }

            function sum(pair: Pair): Int {
                return pair.left + pair.right
            }
            compilerSourceFile\\tMain.range
            @main {
                let pair: Pair(left: 3, right: 4)
                return sum(pair: pair)
            }

            """,
            name: "PairMemoryGraph.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=1\tstorageCount=1\tdecisionCount=8\n"))
        #expect(result.stdout.contains("memoryLayout\trow=0\tvalues=0,2,8,4"))
        #expect(result.stdout.contains("memoryStorage\trow=0\tvalues=0,19,0,12,1,0"))
        #expect(result.stdout.contains("memoryDecision\trow=2\tvalues=3,14,0,0,1,19"))
        #expect(result.stdout.contains("memoryDecision\trow=3\tvalues=4,23,0,0,1,22"))
        #expect(result.stdout.contains("memoryDecision\trow=5\tvalues=6,4,-1,0,1,3"))
        #expect(result.stdout.contains("memoryDecision\trow=6\tvalues=7,24,0,0,1,19"))
        #expect(result.stdout.contains("memoryDecision\trow=7\tvalues=11,19,0,0,1,19"))
    }

    @Test("MemoryGraph proves scalar Int storage without an aggregate layout")
    func memoryGraphProvesScalarIntStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            compilerSourceFile\tMain.range
            @main {
                let count: Int(7)
                return count
            }

            """,
            name: "ScalarIntMemoryGraph.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=0\tstorageCount=1\tdecisionCount=6\n"))
        #expect(result.stdout.contains("memoryStorage\trow=0\tvalues=0,"))
        #expect(result.stdout.contains(",-1,"))
        #expect(result.stdout.contains("memoryDecision\trow=4\tvalues=10,"))
        #expect(result.stdout.contains("memoryDecision\trow=5\tvalues=11,"))
    }

    @Test("Typed syntax preserves language ABI provenance and signature-only functions")
    func typedSyntaxPreservesLanguageABIProvenance() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerTypedSyntax
            @language
            construct IntBuffer {}
            @language
            function intBufferCreate(capacity: Int): IntBuffer
            @language
            function intBufferDestroy(buffer: IntBuffer): Int
            @main {
                return 0
            }

            """,
            name: "LanguageABIProvenance.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("typedSyntax\tvalid=true"))
        #expect(result.stdout.contains("declarationCount=3"))
        #expect(result.stdout.components(separatedBy: "languageABI=1").count == 4)
        #expect(result.stdout.contains("functionCount=2"))
        #expect(result.stdout.contains("bodyStart=113\tbodyEnd=113"))
    }

    @Test("MemoryGraph owns and explicitly consumes an opaque IntBuffer handle")
    func memoryGraphProvesOpaqueIntBufferOwnership() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try runTypedSyntaxFixture(
            source: opaqueIntBufferFixture(body: """
                let buffer: IntBuffer(intBufferCreate(capacity: 4))
                return intBufferDestroy(buffer: buffer)
            """),
            name: "OpaqueIntBufferOwnership.range",
            directory: directory
        )
        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=0\tstorageCount=1\tdecisionCount=5\n"))
        #expect(result.stdout.contains("memoryStorage\trow=0\tvalues=0,11,0,6,1,0"))
        #expect(result.stdout.contains("memoryDecision\trow=1\tvalues=3,8,0,0,1,11"))
        #expect(result.stdout.contains("memoryDecision\trow=2\tvalues=5,11,0,0,0,11"))
        #expect(result.stdout.contains("memoryDecision\trow=3\tvalues=7,13,0,0,1,11"))
    }

    @Test("Typed IR cites opaque IntBuffer initialization and consume decisions")
    func typedIRCarriesOpaqueIntBufferOwnership() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = opaqueIntBufferFixture(body: """
            let buffer: IntBuffer(intBufferCreate(capacity: 4))
            return intBufferDestroy(buffer: buffer)
        """).replacingOccurrences(of: "compilerMemoryGraph", with: "compilerTypedIR")
        let result = try runTypedSyntaxFixture(source: source, name: "OpaqueIntBufferTypedIR.range", directory: directory)
        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("typedIR\tvalid=true\tfunctionCount=1"))
        #expect(result.stdout.contains("operationCount=7"))
        #expect(result.stdout.contains("typedIROperation\trow=0\tvalues=8,6,13,0,0,1,11,1"))
        #expect(result.stdout.contains("typedIROperation\trow=5\tvalues=13,6,6,0,0,11,3,3"))
    }

    @Test("MemoryGraph rejects an opaque handle without explicit destruction")
    func memoryGraphRejectsOpaqueIntBufferMissingDestroy() throws {
        let result = try runOpaqueIntBufferFailureFixture(body: """
            let buffer: IntBuffer(intBufferCreate(capacity: 4))
            return 0
        """, name: "OpaqueIntBufferMissingDestroy.range")
        #expect(result.exitCode == 65)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph rejects opaque handle double destruction")
    func memoryGraphRejectsOpaqueIntBufferDoubleDestroy() throws {
        let result = try runOpaqueIntBufferFailureFixture(body: """
            let buffer: IntBuffer(intBufferCreate(capacity: 4))
            let first: Int(intBufferDestroy(buffer: buffer))
            return intBufferDestroy(buffer: buffer)
        """, name: "OpaqueIntBufferDoubleDestroy.range")
        #expect(result.exitCode == 65)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph rejects opaque handle use after destruction")
    func memoryGraphRejectsOpaqueIntBufferUseAfterDestroy() throws {
        let result = try runOpaqueIntBufferFailureFixture(body: """
            let buffer: IntBuffer(intBufferCreate(capacity: 4))
            let status: Int(intBufferDestroy(buffer: buffer))
            return intBufferCount(buffer: buffer)
        """, name: "OpaqueIntBufferUseAfterDestroy.range", includeCount: true)
        #expect(result.exitCode == 65)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph rejects returning an opaque handle without transfer")
    func memoryGraphRejectsOpaqueIntBufferReturnWithoutTransfer() throws {
        let result = try runOpaqueIntBufferFailureFixture(body: """
            let buffer: IntBuffer(intBufferCreate(capacity: 4))
            return buffer
        """, name: "OpaqueIntBufferReturn.range")
        #expect(result.exitCode == 65)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph does not infer opacity from an ordinary empty construct")
    func memoryGraphRejectsOrdinaryEmptyConstructAsOpaque() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Empty {}
            @main {
                return 0
            }

            """,
            name: "OrdinaryEmptyConstruct.range",
            directory: directory
        )
        #expect(result.exitCode == 65)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph rejects malformed opaque destructor ABI")
    func memoryGraphRejectsMalformedIntBufferDestructorABI() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @language
            construct IntBuffer {}
            @language
            function intBufferCreate(capacity: Int): IntBuffer
            @language
            function intBufferDestroy(buffer: Int): Int
            @main {
                let buffer: IntBuffer(intBufferCreate(capacity: 4))
                return intBufferDestroy(buffer: buffer)
            }

            """,
            name: "MalformedIntBufferDestructorABI.range",
            directory: directory
        )
        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph proves mutable scalar Int writes")
    func memoryGraphProvesMutableScalarIntWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @main {
                state count: Int(7)
                count: 8
                return count
            }

            """,
            name: "MutableScalarIntMemoryGraph.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=0\tstorageCount=1\tdecisionCount=7\n"))
        #expect(result.stdout.contains("memoryDecision\trow=4\tvalues=10,"))
        #expect(result.stdout.contains(",2,"))
        #expect(result.stdout.contains("memoryDecision\trow=6\tvalues=11,"))
        #expect(result.stdout.contains(",2,"))
    }

    @Test("MemoryGraph rejects mutable access to scalar let storage")
    func memoryGraphRejectsScalarIntWriteThroughLet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @main {
                let count: Int(7)
                count: 8
                return count
            }

            """,
            name: "ImmutableScalarIntMemoryGraph.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph destroys branch-local scalar storage at its lexical region")
    func memoryGraphProvesFallthroughIfLexicalLifetime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @main {
                let outer: Int(1)
                if 1 {
                    state inner: Int(2)
                    inner: 3
                }
                return outer
            }

            """,
            name: "FallthroughIfLexicalLifetime.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=0\tstorageCount=2\tdecisionCount=12\n"))
        #expect(result.stdout.contains("memoryStorage\trow=0\tvalues=0,3,-1,1,1,0"))
        #expect(result.stdout.contains("memoryStorage\trow=1\tvalues=1,8,-1,6,1,0"))
        #expect(result.stdout.contains("memoryDecision\trow=6\tvalues=7,6,1,-1,1,8"))
        #expect(result.stdout.contains("memoryDecision\trow=7\tvalues=7,13,0,-1,1,3"))
        #expect(result.stdout.contains("memoryDecision\trow=8\tvalues=10,11,1,-1,2,9"))
        #expect(result.stdout.contains("memoryDecision\trow=9\tvalues=10,12,0,-1,1,12"))
    }

    @Test("MemoryGraph applies lexical destruction to branch-local aggregates")
    func memoryGraphProvesAggregateFallthroughIfLexicalLifetime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Pair {
                let left: Int
                let right: Int
            }
            @main {
                if 1 {
                    let pair: Pair(left: 1, right: 2)
                }
                return 0
            }

            """,
            name: "AggregateFallthroughIfLexicalLifetime.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=1\tstorageCount=1\tdecisionCount=6\n"))
        #expect(result.stdout.contains("memoryStorage\trow=0\tvalues=0,"))
    }

    @Test("SemanticGraph rejects branch-local storage use after its region")
    func semanticGraphRejectsBranchLocalUseAfterFallthroughIf() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @main {
                if 1 {
                    let inner: Int(2)
                }
                return inner
            }

            """,
            name: "EscapedBranchLocalName.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidSemanticGraph\n\n")
    }

    @Test("MemoryGraph copies scalar returns and destroys storage on each reachable path")
    func memoryGraphProvesScalarEarlyReturnPathDestruction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @main {
                let outer: Int(1)
                if 1 {
                    let inner: Int(2)
                    return inner
                }
                return outer
            }

            """,
            name: "ScalarEarlyReturnLifetime.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=0\tstorageCount=2\tdecisionCount=13\n"))
        #expect(result.stdout.contains("memoryDecision\trow=4\tvalues=5,3,0,-1,0,3"))
        #expect(result.stdout.contains("memoryDecision\trow=5\tvalues=5,8,1,-1,0,8"))
        #expect(result.stdout.contains("memoryDecision\trow=6\tvalues=7,10,0,-1,1,3"))
        #expect(result.stdout.contains("memoryDecision\trow=7\tvalues=7,10,1,-1,1,8"))
        #expect(result.stdout.contains("memoryDecision\trow=8\tvalues=7,12,0,-1,1,3"))
    }

    @Test("MemoryGraph rejects branch-local aggregate return without transfer placement")
    func memoryGraphRejectsAggregateEarlyReturnWithoutPlacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Pair {
                let left: Int
                let right: Int
            }
            @main {
                if 1 {
                    let pair: Pair(left: 1, right: 2)
                    return pair
                }
                return 0
            }

            """,
            name: "AggregateEarlyReturnWithoutPlacement.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("Typed syntax rejects statements after a region return")
    func typedSyntaxRejectsStatementAfterLexicalReturn() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            @main {
                if 1 {
                    let inner: Int(2)
                    return inner
                    let unreachable: Int(3)
                }
                return 0
            }

            """,
            name: "StatementAfterLexicalReturn.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidTypedSyntaxSnapshot\n\n")
    }

    @Test("Native compiler carries MemoryGraph decisions through typed IR")
    func nativeCompilerCarriesMemoryGraphDecisionsThroughTypedIR() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerTypedIR
            compilerSourceFile\\tPair.range
            construct Pair {
                let left: Int
                let right: Int
            }

            function sum(pair: Pair): Int {
                return pair.left + pair.right
            }
            compilerSourceFile\\tMain.range
            @main {
                let pair: Pair(left: 3, right: 4)
                return sum(pair: pair)
            }

            """,
            name: "PairTypedIR.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("typedIR\tvalid=true\tfunctionCount=2\toperationCount=15\n"))
        #expect(result.stdout.contains("typedIROperation\trow=4\tvalues=14,12,9,0,0,0,3,0"))
        #expect(result.stdout.contains("typedIROperation\trow=6\tvalues=14,12,1,0,0,2,0,2"))
        #expect(result.stdout.contains("typedIROperation\trow=9\tvalues=19,12,7,0,0,14,0,1"))
        #expect(result.stdout.contains("typedIROperation\trow=10\tvalues=19,12,14,0,0,1,0,7"))
        #expect(result.stdout.contains("typedIROperation\trow=11\tvalues=19,12,10,0,0,19,0,4"))
        #expect(result.stdout.contains("typedIROperation\trow=12\tvalues=21,12,4,0,0,3,19,3"))
        #expect(result.stdout.contains("typedIROperation\trow=13\tvalues=24,12,6,0,0,19,0,6"))
    }

    @Test("Native compiler lowers renamed fixed aggregate without construct runtime")
    func nativeCompilerLowersRenamedFixedAggregateWithoutConstructRuntime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryLLVMText
            compilerSourceFile\\tDuo.range
            construct Duo {
                let first: Int
                let second: Int
            }

            function total(value: Duo): Int {
                return value.first + value.second
            }
            compilerSourceFile\\tMain.range
            @main {
                let value: Duo(second: 4, first: 3)
                return total(value: value)
            }

            """,
            name: "DuoFixedLLVM.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("= type { i32, i32 }"))
        #expect(result.stdout.contains("insertvalue"))
        #expect(result.stdout.contains("extractvalue"))
        #expect(result.stdout.contains("alloca"))
        #expect(!result.stdout.contains("rangeConstruct"))
        #expect(!result.stdout.contains("malloc"))
        #expect(!result.stdout.contains("calloc"))

        let llvm = directory.appendingPathComponent("DuoFixedLLVM.ll")
        let executable = directory.appendingPathComponent("DuoFixedLLVM")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-x", "ir", llvm.path, "-o", executable.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)

        let executableResult = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(executableResult.exitCode == 7)
        #expect(executableResult.stdout.isEmpty)
        #expect(executableResult.stderr.isEmpty)
    }

    @Test("MemoryGraph transfers returned aggregate into caller storage")
    func memoryGraphTransfersReturnedAggregateIntoCallerStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            compilerSourceFile\\tDuo.range
            construct Duo {
                let first: Int
                let second: Int
            }

            function makeDuo(): Duo {
                return Duo(second: 4, first: 3)
            }
            compilerSourceFile\\tMain.range
            @main {
                let value: Duo(makeDuo())
                return value.first + value.second
            }

            """,
            name: "ReturnedDuoMemoryGraph.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=1\tstorageCount=1\tdecisionCount=10\n"))
        #expect(result.stdout.contains("memoryStorage\trow=0\tvalues=0,15,0,12,1,0"))
        #expect(result.stdout.contains("memoryDecision\trow=2\tvalues=3,14,0,0,1,15"))
        #expect(result.stdout.contains("memoryDecision\trow=4\tvalues=7,21,0,0,1,15"))
        #expect(result.stdout.contains("memoryDecision\trow=5\tvalues=8,14,0,0,1,5"))
        #expect(result.stdout.contains("memoryDecision\trow=6\tvalues=9,3,-1,0,1,10"))
        #expect(result.stdout.contains("memoryDecision\trow=7\tvalues=10,17,0,0,1,16"))
        #expect(result.stdout.contains("memoryDecision\trow=9\tvalues=11,15,0,0,1,15"))
        #expect(!result.stdout.contains("values=7,10,"))
    }

    @Test("MemoryGraph records binding as a shared alias without placement")
    func nativeCompilerRecordsBindingAliasWithoutPlacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            compilerSourceFile\\tPair.range
            construct Pair {
                let left: Int
                let right: Int
            }
            compilerSourceFile\\tUser.range
            construct User {
                let tag: Int
                binding pair: Pair
            }
            compilerSourceFile\\tMain.range
            @main {
                let pair: Pair(left: 3, right: 4)
                let user: User(tag: 1, pair: $pair)
                return pair.left + pair.right
            }

            """,
            name: "BindingAliasMemoryGraph.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("memoryGraph\tvalid=true"))
        #expect(result.stdout.contains("memoryDecision\trow="))
        #expect(result.stdout.contains("values=12,"))
        #expect(!result.stdout.contains("memoryStorage\trow=2"))
    }

    @Test("MemoryGraph allows multiple shared bindings to one storage")
    func memoryGraphAllowsSharedBindingAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Pair {
                let left: Int
                let right: Int
            }
            construct User {
                let tag: Int
                binding pair: Pair
            }
            @main {
                let pair: Pair(left: 3, right: 4)
                let first: User(tag: 1, pair: $pair)
                let second: User(tag: 2, pair: $pair)
                return pair.left + pair.right
            }

            """,
            name: "SharedBindingAliases.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("memoryGraph\tvalid=true\tlayoutCount=2\tstorageCount=3\tdecisionCount=21\n"))
        #expect(result.stdout.components(separatedBy: "values=12,").count == 3)
    }

    @Test("MemoryGraph rejects a unique write while shared binding is live")
    func memoryGraphRejectsWriteConflictingWithSharedBinding() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Pair {
                let left: Int
                let right: Int
            }
            construct User {
                let tag: Int
                binding pair: Pair
            }
            @main {
                state pair: Pair(left: 3, right: 4)
                let user: User(tag: 1, pair: $pair)
                pair: Pair(left: 5, right: 6)
                return pair.left + pair.right
            }

            """,
            name: "SharedBindingWriteConflict.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("Native compiler executes a unique write through a binding member")
    func nativeCompilerExecutesUniqueBindingMemberWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            construct Pair {
                let left: Int
                let right: Int
            }
            construct User {
                let tag: Int
                binding pair: Pair
            }
            @main {
                state pair: Pair(left: 1, right: 2)
                let user: User(tag: 1, pair: $pair)
                user.pair: Pair(left: 3, right: 4)
                return pair.left + pair.right
            }

            """,
            name: "OrdinaryUniqueBindingMemberWrite.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.components(separatedBy: " = type { ").count == 3)
        #expect(result.stdout.contains("%storage0 = alloca"))
        #expect(result.stdout.contains("%storage1 = alloca"))
        #expect(result.stdout.contains("%updated30_0"))
        #expect(result.stdout.contains("ptr %storage0"))
        #expect(!result.stdout.contains("rangeConstruct"))

        let llvm = directory.appendingPathComponent("UniqueBindingMemberWrite.ll")
        let executable = directory.appendingPathComponent("UniqueBindingMemberWrite")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-x", "ir", llvm.path, "-o", executable.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)
        let executableResult = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(executableResult.exitCode == 7)
        #expect(executableResult.stdout.isEmpty)
        #expect(executableResult.stderr.isEmpty)
    }

    @Test("MemoryGraph rejects shared and unique binding aliases")
    func memoryGraphRejectsSharedAndUniqueBindingAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Pair {
                let left: Int
                let right: Int
            }
            construct User {
                let tag: Int
                binding pair: Pair
            }
            @main {
                state pair: Pair(left: 1, right: 2)
                let reader: User(tag: 1, pair: $pair)
                let writer: User(tag: 2, pair: $pair)
                writer.pair: Pair(left: 3, right: 4)
                return pair.left + pair.right
            }

            """,
            name: "SharedUniqueBindingConflict.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph rejects two unique binding aliases")
    func memoryGraphRejectsTwoUniqueBindingAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            construct Pair {
                let left: Int
                let right: Int
            }
            construct User {
                let tag: Int
                binding pair: Pair
            }
            @main {
                state pair: Pair(left: 1, right: 2)
                let first: User(tag: 1, pair: $pair)
                let second: User(tag: 2, pair: $pair)
                first.pair: Pair(left: 3, right: 4)
                second.pair: Pair(left: 5, right: 6)
                return pair.left + pair.right
            }

            """,
            name: "UniqueBindingConflict.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("Native compiler executes returned aggregate ownership transfer")
    func nativeCompilerExecutesReturnedAggregateOwnershipTransfer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryLLVMText
            compilerSourceFile\\tDuo.range
            construct Duo {
                let first: Int
                let second: Int
            }

            function makeDuo(): Duo {
                return Duo(second: 4, first: 3)
            }
            compilerSourceFile\\tMain.range
            @main {
                let value: Duo(makeDuo())
                return value.first + value.second
            }

            """,
            name: "ReturnedDuoLLVM.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("define %Range.Fixed."))
        #expect(result.stdout.contains("call %Range.Fixed."))
        #expect(result.stdout.contains("ret %Range.Fixed."))
        #expect(result.stdout.contains("alloca"))
        #expect(result.stdout.contains("store"))
        #expect(result.stdout.contains("extractvalue"))
        #expect(!result.stdout.contains("rangeConstruct"))
        #expect(!result.stdout.contains("malloc"))
        #expect(!result.stdout.contains("calloc"))

        let llvm = directory.appendingPathComponent("ReturnedDuoLLVM.ll")
        let executable = directory.appendingPathComponent("ReturnedDuoLLVM")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-x", "ir", llvm.path, "-o", executable.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)
        let executableResult = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(executableResult.exitCode == 7)
        #expect(executableResult.stdout.isEmpty)
        #expect(executableResult.stderr.isEmpty)
    }

    @Test("Typed IR preserves immutable and mutable caller storage policy")
    func typedIRPreservesCallerStoragePolicy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerTypedIR
            compilerSourceFile\tDuo.range
            construct Duo {
                let first: Int
                let second: Int
            }
            function makeFirst(): Duo {
                return Duo(second: 2, first: 1)
            }
            function makeSecond(): Duo {
                return Duo(first: 3, second: 6)
            }
            compilerSourceFile\tMain.range
            @main {
                let first: Duo(makeFirst())
                state second: Duo(makeSecond())
                return first.first + second.second
            }

            """,
            name: "CallerStoragePolicy.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("typedIR\tvalid=true\tfunctionCount=3\toperationCount=28\n"))
        #expect(result.stdout.contains("typedIROperation\trow=15\tvalues=23,20,14,0,0,1,0,15"))
        #expect(result.stdout.contains("typedIROperation\trow=20\tvalues=26,20,14,0,1,2,0,16"))
    }

    @Test("Native compiler executes unique state aggregate write")
    func nativeCompilerExecutesUniqueStateAggregateWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryLLVMText
            construct Duo {
                let first: Int
                let second: Int
            }
            function makeDuo(): Duo {
                return Duo(first: 1, second: 2)
            }
            @main {
                state value: Duo(makeDuo())
                value: Duo(second: 4, first: 3)
                return value.first + value.second
            }

            """,
            name: "StateAggregateWrite.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("%updated"))
        #expect(result.stdout.components(separatedBy: "store %Range.Fixed.").count == 3)
        #expect(result.stdout.contains("ptr %storage0"))
        #expect(!result.stdout.contains("rangeConstruct"))
        #expect(!result.stdout.contains("malloc"))
        #expect(!result.stdout.contains("calloc"))

        let llvm = directory.appendingPathComponent("StateAggregateWrite.ll")
        let executable = directory.appendingPathComponent("StateAggregateWrite")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-x", "ir", llvm.path, "-o", executable.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)
        let executableResult = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(executableResult.exitCode == 7)
        #expect(executableResult.stdout.isEmpty)
        #expect(executableResult.stderr.isEmpty)
    }

    @Test("MemoryGraph rejects identical aggregate write through let")
    func memoryGraphRejectsAggregateWriteThroughLet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryLLVMText
            construct Duo {
                let first: Int
                let second: Int
            }
            function makeDuo(): Duo {
                return Duo(first: 1, second: 2)
            }
            @main {
                let value: Duo(makeDuo())
                value: Duo(second: 4, first: 3)
                return value.first + value.second
            }

            """,
            name: "LetAggregateWrite.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("Native compiler iterates returned functions and aggregate fields")
    func nativeCompilerIteratesReturnedFunctionsAndAggregateFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryLLVMText
            compilerSourceFile\tTriple.range
            construct Triple {
                let first: Int
                let middle: Int
                let last: Int
            }
            function makeFirst(): Triple {
                return Triple(middle: 2, last: 4, first: 1)
            }
            function makeSecond(): Triple {
                return Triple(last: 6, first: 3, middle: 5)
            }
            compilerSourceFile\tMain.range
            @main {
                let first: Triple(makeFirst())
                state second: Triple(makeSecond())
                return first.first + second.last
            }

            """,
            name: "ReturnedTripleLLVM.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("= type { i32, i32, i32 }"))
        #expect(result.stdout.components(separatedBy: "define %Range.Fixed.").count == 3)
        #expect(result.stdout.components(separatedBy: "call %Range.Fixed.").count == 3)
        #expect(result.stdout.contains("%storage0 = alloca"))
        #expect(result.stdout.contains("%storage1 = alloca"))
        #expect(result.stdout.contains(", 2\n"))
        #expect(!result.stdout.contains("rangeConstruct"))
        #expect(!result.stdout.contains("malloc"))
        #expect(!result.stdout.contains("calloc"))

        let llvm = directory.appendingPathComponent("ReturnedTripleLLVM.ll")
        let executable = directory.appendingPathComponent("ReturnedTripleLLVM")
        try result.stdout.write(to: llvm, atomically: true, encoding: .utf8)
        let clangResult = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "-Wno-override-module", "-x", "ir", llvm.path, "-o", executable.path]
        )
        #expect(clangResult.exitCode == 0)
        #expect(clangResult.stderr.isEmpty)
        let executableResult = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(executableResult.exitCode == 7)
        #expect(executableResult.stdout.isEmpty)
        #expect(executableResult.stderr.isEmpty)
    }

    @Test("MemoryGraph rejects callee-local aggregate return without transfer placement")
    func memoryGraphRejectsCalleeLocalAggregateReturnWithoutTransferPlacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            compilerSourceFile\\tDuo.range
            construct Duo {
                let first: Int
                let second: Int
            }

            function makeDuo(): Duo {
                let temporary: Duo(first: 3, second: 4)
                return temporary
            }
            compilerSourceFile\\tMain.range
            @main {
                let value: Duo(makeDuo())
                return value.first + value.second
            }

            """,
            name: "UnsupportedCalleeLocalTransfer.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
    }

    @Test("MemoryGraph rejects returned local aggregate before placement")
    func memoryGraphRejectsReturnedLocalAggregateBeforePlacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runTypedSyntaxFixture(
            source: """
            compilerMemoryGraph
            compilerSourceFile\\tDuo.range
            construct Duo {
                let first: Int
                let second: Int
            }
            compilerSourceFile\\tMain.range
            @main {
                let value: Duo(first: 3, second: 4)
                return value
            }

            """,
            name: "ReturnedLocalDuo.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 65)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "compilerError\tkind=invalidMemoryGraph\n\n")
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

    @Test("Native source-set declarations render from typed declaration tables")
    func nativeSourceSetDeclarationsRenderFromTypedDeclarationTables() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("TypedNativeDeclarations.range")
        try """
        compilerNativeSourceSetLLVMText
        compilerSourceFile\\tRuntime.range
        function compileRangeNativeSource(source: String): String {
            return source
        }

        @language
        function firstExternal(value: Int, enabled: Bool): String

        @language
        function secondExternal(): Int
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
        let first = "declare ptr @firstExternal(i32 %value, i1 %enabled)"
        let second = "declare i32 @secondExternal()"
        #expect(result.stdout.contains(first))
        #expect(result.stdout.contains(second))
        #expect(result.stdout.contains("define ptr @compileRangeNativeSource(ptr %source)"))
        #expect(!result.stdout.contains("declare ptr @compileRangeNativeSource"))
        let firstRange = result.stdout.range(of: first)
        let secondRange = result.stdout.range(of: second)
        #expect(firstRange != nil)
        #expect(secondRange != nil)
        if let firstRange, let secondRange {
            #expect(firstRange.lowerBound < secondRange.lowerBound)
        }
        #expect(!result.stdout.contains("kind=invalidTypedDeclarations"))
    }

    @Test("Selected compiler bodies execute through canonical typed arenas")
    func selectedCompilerBodiesExecuteThroughCanonicalTypedArenas() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = """
        compilerNativeSourceSetSelectedStats
        function compilerSourceFileTableColumnCount(): Int {
            return 5
        }

        function compilerSourceRoleProject(): Int {
            return 3
        }

        """
        let first = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerConstantBodyArenaFirst.range",
            directory: directory
        )
        let second = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerConstantBodyArenaSecond.range",
            directory: directory
        )

        #expect(first.timedOut == false)
        #expect(first.exitCode == 0)
        #expect(first.stderr.isEmpty)
        #expect(first.stdout.contains("typedParseAttempts=2"))
        #expect(first.stdout.contains("arenaParsed=2"))
        #expect(first.stdout.contains("legacyParsed=0"))
        #expect(first.stdout.contains("arenaCreates=2"))
        #expect(first.stdout.contains("arenaDestroys=2"))
        #expect(first.stdout.contains("arenaRecordBytes=0"))
        #expect(first.stdout.contains("committedFailures=0"))
        #expect(first.stdout == second.stdout)
        #expect(second.exitCode == 0)
        #expect(second.stderr.isEmpty)
    }

    @Test("General typed body shape executes through a canonical arena")
    func generalTypedBodyShapeExecutesThroughCanonicalArena() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = """
        compilerNativeSourceSetSelectedStats
        function compilerSourceFileTableColumnCount(value: Int): Int {
            return value + 1
        }

        """
        let result = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerTypedBodyUnsupported.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("typedParseAttempts=1"))
        #expect(result.stdout.contains("arenaParsed=1"))
        #expect(result.stdout.contains("legacyParsed=0"))
        #expect(result.stdout.contains("arenaCreates=1"))
        #expect(result.stdout.contains("arenaDestroys=1"))
        #expect(result.stdout.contains("committedFailures=0"))
    }

    @Test("Bare call statement flows through typed MemoryGraph MIR and LLVM")
    func bareCallStatementFlowsThroughTypedPipeline() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualTransitionFunctionID_0_
        function appendValue(buffer: IntBuffer): Int {
            intBufferAppend(buffer: buffer, value: 7)
            return intBufferCount(buffer: buffer)
        }

        """
        let result = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerBareCallStatement.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=1"))
        #expect(result.stdout.contains("exactCount=1"))
        #expect(result.stdout.contains("typedInvalidCount=0"))
        #expect(result.stdout.contains("typedPlaceholderCount=0"))
        #expect(result.stdout.contains("typedRecordNonzeroCount=0"))
    }

    @Test("One-pass typed admission falls back only for unsupported syntax")
    func onePassTypedAdmissionFallsBackForUnsupportedSyntax() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = """
        compilerNativeSourceSetSelectedStats
        function compilerSourceFileTableColumnCount(value: Int): String {
            return "value \\(value)"
        }

        """
        let result = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerOnePassUnsupportedFallback.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("supportedCount=0"))
        #expect(result.stdout.contains("typedParseAttempts=1"))
        #expect(result.stdout.contains("arenaParsed=0"))
        #expect(result.stdout.contains("legacyParsed=1"))
        #expect(result.stdout.contains("arenaCreates=1"))
        #expect(result.stdout.contains("arenaDestroys=1"))
        #expect(result.stdout.contains("committedFailures=0"))
    }

    @Test("Canonical body arena parses the actual expression type inference family")
    func canonicalBodyArenaParsesActualExpressionTypeInferenceFamily() throws {
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
        let fixture = """
        compilerNativeBodyArenaStats
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let result = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerActualBodyArenaStats.range",
            directory: directory
        )
        let repeated = try runTypedSyntaxFixture(
            source: fixture,
            name: "CompilerActualBodyArenaStatsRepeated.range",
            directory: directory
        )

        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        let arenaRows = result.stdout.components(separatedBy: "\\n")
        let rangeTypeLine = arenaRows.first {
            $0.contains("name=compilerCoreExpressionSummaryRangeTypeForLLVM")
        }
        let inferredTypeLine = arenaRows.first {
            $0.contains("name=compilerCoreInferExpressionSummaryType")
        }
        #expect(repeated.timedOut == false)
        #expect(repeated.exitCode == 0)
        #expect(repeated.stderr.isEmpty)
        #expect(repeated.stdout == result.stdout)
        #expect(result.stdout.contains("runtimeBuiltinCount=34"))
        #expect(result.stdout.contains("runtimeBuiltinABIValid=true"))
        #expect(rangeTypeLine?.contains("valid=true") == true)
        #expect(inferredTypeLine?.contains("valid=true") == true)
        let rangeTypeFields = Dictionary(uniqueKeysWithValues: (rangeTypeLine ?? "").components(separatedBy: "\\t").compactMap { field -> (String, String)? in
            let parts = field.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        let inferredTypeFields = Dictionary(uniqueKeysWithValues: (inferredTypeLine ?? "").components(separatedBy: "\\t").compactMap { field -> (String, String)? in
            let parts = field.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        #expect(rangeTypeFields["nodes"] == "577")
        #expect(rangeTypeFields["edges"] == "576")
        #expect(rangeTypeFields["semanticStatus"] == "0")
        #expect(rangeTypeFields["semanticValid"] == "true")
        #expect(rangeTypeFields["symbols"] == "18")
        // These diagnostic counts may move with canonical graph detail; the focused
        // final-artifact equality oracle below is the compatibility authority.
        #expect(rangeTypeFields["resolutions"] == "231")
        #expect(rangeTypeFields["cfgStatus"] == "0")
        #expect(rangeTypeFields["cfgValid"] == "true")
        #expect(rangeTypeFields["cfgBlocks"] == "43")
        #expect(rangeTypeFields["cfgEdges"] == "46")
        #expect(rangeTypeFields["conditionTerminators"] == "21")
        #expect(rangeTypeFields["returnTerminators"] == "18")
        #expect(rangeTypeFields["mirBeforeMemoryStatus"] == "-1")
        #expect(rangeTypeFields["memoryStatus"] == "0")
        #expect(rangeTypeFields["memoryValid"] == "true")
        #expect(rangeTypeFields["memoryFacts"] == "814")
        #expect(rangeTypeFields["memoryValueFacts"] == "595")
        #expect(rangeTypeFields["memoryPlacementFacts"] == "0")
        #expect(rangeTypeFields["memoryAccessFacts"] == "83")
        #expect(rangeTypeFields["memoryPassFacts"] == "136")
        #expect(rangeTypeFields["memoryLifetimeFacts"] == "0")
        #expect(rangeTypeFields["memoryOwnedValueFacts"] == "14")
        #expect(rangeTypeFields["memoryBorrowedValueFacts"] == "4")
        #expect(rangeTypeFields["memoryReadFacts"] == "83")
        #expect(rangeTypeFields["memoryArgumentPassFacts"] == "118")
        #expect(rangeTypeFields["memoryReturnEscapeFacts"] == "18")
        #expect(rangeTypeFields["memoryTransferFacts"] == "0")
        #expect(rangeTypeFields["memoryDestructionFacts"] == "0")
        #expect(rangeTypeFields["mirStatus"] == "0")
        #expect(rangeTypeFields["mirValid"] == "true")
        #expect(rangeTypeFields["mirValidationCode"] == "0")
        #expect(rangeTypeFields["mirValues"] == "236")
        #expect(rangeTypeFields["mirBlocks"] == "43")
        #expect(rangeTypeFields["mirOperations"] == "275")
        #expect(rangeTypeFields["mirOperands"] == "301")
        #expect(rangeTypeFields["llvmEmissionValid"] == "true")
        #expect(rangeTypeFields["llvmRenderedLength"] == "11147")
        #expect(rangeTypeFields["llvmRecordLength"] == "0")
        #expect(rangeTypeFields["llvmNextTemporary"] == "187")
        #expect(rangeTypeFields["llvmNextBranch"] == "21")
        #expect(inferredTypeFields["nodes"] == "570")
        #expect(inferredTypeFields["edges"] == "569")
        #expect(inferredTypeFields["semanticStatus"] == "0")
        #expect(inferredTypeFields["semanticValid"] == "true")
        #expect(inferredTypeFields["symbols"] == "18")
        #expect(inferredTypeFields["resolutions"] == "227")
        #expect(inferredTypeFields["cfgStatus"] == "0")
        #expect(inferredTypeFields["cfgValid"] == "true")
        #expect(inferredTypeFields["cfgBlocks"] == "43")
        #expect(inferredTypeFields["cfgEdges"] == "46")
        #expect(inferredTypeFields["conditionTerminators"] == "21")
        #expect(inferredTypeFields["returnTerminators"] == "18")
        #expect(inferredTypeFields["mirBeforeMemoryStatus"] == "-1")
        #expect(inferredTypeFields["memoryStatus"] == "0")
        #expect(inferredTypeFields["memoryValid"] == "true")
        #expect(inferredTypeFields["memoryFacts"] == "805")
        #expect(inferredTypeFields["memoryValueFacts"] == "588")
        #expect(inferredTypeFields["memoryPlacementFacts"] == "0")
        #expect(inferredTypeFields["memoryAccessFacts"] == "82")
        #expect(inferredTypeFields["memoryPassFacts"] == "135")
        #expect(inferredTypeFields["memoryLifetimeFacts"] == "0")
        #expect(inferredTypeFields["memoryOwnedValueFacts"] == "14")
        #expect(inferredTypeFields["memoryBorrowedValueFacts"] == "4")
        #expect(inferredTypeFields["memoryReadFacts"] == "82")
        #expect(inferredTypeFields["memoryArgumentPassFacts"] == "117")
        #expect(inferredTypeFields["memoryReturnEscapeFacts"] == "18")
        #expect(inferredTypeFields["memoryTransferFacts"] == "0")
        #expect(inferredTypeFields["memoryDestructionFacts"] == "0")
        #expect(inferredTypeFields["mirStatus"] == "0")
        #expect(inferredTypeFields["mirValid"] == "true")
        #expect(inferredTypeFields["mirValidationCode"] == "0")
        #expect(inferredTypeFields["mirValues"] == "232")
        #expect(inferredTypeFields["mirBlocks"] == "43")
        #expect(inferredTypeFields["mirOperations"] == "271")
        #expect(inferredTypeFields["mirOperands"] == "296")
        #expect(inferredTypeFields["llvmEmissionValid"] == "true")
        #expect(inferredTypeFields["llvmRenderedLength"] == "11002")
        #expect(inferredTypeFields["llvmRecordLength"] == "0")
        #expect(inferredTypeFields["llvmNextTemporary"] == "183")
        #expect(inferredTypeFields["llvmNextBranch"] == "21")
        let summary = arenaRows.first
        let summaryFields = Dictionary(uniqueKeysWithValues: (summary ?? "").components(separatedBy: "\\t").compactMap { field -> (String, String)? in
            let parts = field.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        #expect(summaryFields["functionCount"] == summaryFields["destroyCount"])
        #expect(summaryFields["transitionSupportedCount"] == summaryFields["transitionPipelineValidCount"])
        #expect(summaryFields["transitionArenaFailureCount"] == "0")
        #expect(summaryFields["transitionSemanticFailureCount"] == "0")
        #expect(summaryFields["transitionCFGFailureCount"] == "0")
        #expect(summaryFields["transitionMemoryFailureCount"] == "0")
        #expect(summaryFields["transitionMIRFailureCount"] == "0")
        #expect(summaryFields["transitionLLVMFailureCount"] == "0")
    }

    @Test("Canonical body arena diagnoses unresolved typed identifiers deterministically")
    func canonicalBodyArenaDiagnosesUnresolvedTypedIdentifiersDeterministically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyArenaStats
        function unresolvedValue(): String {
            return missingValue
        }

        """
        let first = try runTypedSyntaxFixture(source: fixture, name: "UnresolvedTypedBodyFirst.range", directory: directory)
        let second = try runTypedSyntaxFixture(source: fixture, name: "UnresolvedTypedBodySecond.range", directory: directory)
        #expect(first.timedOut == false)
        #expect(first.exitCode == 0)
        #expect(first.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(first.stdout.contains("name=unresolvedValue\\tvalid=true"))
        #expect(first.stdout.contains("semanticStatus=-1\\tsemanticValid=false"))
        #expect(first.stdout.contains("functionCount=1"))
        #expect(first.stdout.contains("destroyCount=1"))
    }

    @Test("Typed MIR LLVM exactly matches legacy lowering for the actual inference family")
    func typedMIRLLVMExactlyMatchesLegacyForActualInferenceFamily() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try repositoryRoot()
        let compilerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"), encoding: .utf8)
        let compilerCoreSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"), encoding: .utf8)
        let lexerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"), encoding: .utf8)
        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualFunction	compilerCoreExpressionSummaryRangeTypeForLLVM\\n
        compilerDualFunction	compilerCoreInferExpressionSummaryType\\n
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CompilerActualInferenceDualLLVM.range", directory: directory, timeout: 360)
        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=2"))
        #expect(result.stdout.components(separatedBy: "exact=true").count == 3)
    }

    @Test("Every transition-supported compiler function has a bounded dual classification")
    func everyTransitionSupportedCompilerFunctionHasBoundedDualClassification() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try repositoryRoot()
        let compilerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"), encoding: .utf8)
        let compilerCoreSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"), encoding: .utf8)
        let lexerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"), encoding: .utf8)
        let fixture = """
        compilerNativeBodyLLVMDualStats
        BATCH_IDS
        compilerDualSkipFunction\tcompilerSemanticGraphIsValid
        compilerDualSkipFunction\tcompilerMemoryGraphIsValid
        compilerDualSkipFunction\tcompilerBodyArenaIsValid
        compilerDualSkipFunction\tcompilerCoreExpressionSummaryRangeTypeForLLVM
        compilerDualSkipFunction\tcompilerCoreInferExpressionSummaryType
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let sourceURL = directory.appendingPathComponent("CompilerTransitionSupportedDualLLVM.range")
        let compiler = root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
        let executable = try TypedSyntaxCompilerCache.shared.executable(for: compiler)
        var totals: [String: Int] = [:]
        var selectedIDs = Set<Int>()
        var functionCount: Int?
        var transitionSupportedTotal: Int?
        var observedMaximumResidentBytes: UInt64 = 0
        var resourceSplitCount = 0
        let requestedStart = Int(ProcessInfo.processInfo.environment["RANGE_DUAL_AUDIT_START"] ?? "") ?? 0
        let requestedEnd = Int(ProcessInfo.processInfo.environment["RANGE_DUAL_AUDIT_END"] ?? "") ?? 1400
        var pendingBatches = stride(from: requestedStart, to: requestedEnd, by: 40).map { $0..<min($0 + 40, requestedEnd) }
        while !pendingBatches.isEmpty {
            let batch = pendingBatches.removeFirst()
            let batchIDs = batch
                .map { "compilerDualTransitionFunctionID_\($0)_" }
                .joined(separator: "\n")
            let batchFixture = fixture.replacingOccurrences(of: "BATCH_IDS", with: batchIDs)
            try batchFixture.write(to: sourceURL, atomically: true, encoding: .utf8)
            let result = try runFixtureExecutable(
                executable: executable,
                source: sourceURL,
                timeout: 240,
                maximumResidentBytes: 1024 * 1024 * 1024
            )
            #expect(result.timedOut == false)
            if result.resourceLimited {
                resourceSplitCount += 1
                #expect(batch.count > 1)
                if batch.count > 1 {
                    let middle = batch.lowerBound + batch.count / 2
                    pendingBatches.insert(middle..<batch.upperBound, at: 0)
                    pendingBatches.insert(batch.lowerBound..<middle, at: 0)
                }
                continue
            }
            #expect(result.exitCode == 0)
            #expect(result.stderr.isEmpty)
            observedMaximumResidentBytes = max(observedMaximumResidentBytes, result.maximumResidentBytes)
            let rows = result.stdout.components(separatedBy: "\\n")
            for row in rows where row.hasPrefix("dualCompatibility\\t") && row.contains("legacyStructuralPhiDefect=true") { print(row) }
            let summary = rows.first ?? ""
            let fields = Dictionary(uniqueKeysWithValues: summary.components(separatedBy: "\\t").compactMap { field -> (String, Int)? in
                let parts = field.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, let value = Int(parts[1]) else { return nil }
                return (String(parts[0]), value)
            })
            if functionCount == nil { functionCount = fields["functionCount"] }
            if transitionSupportedTotal == nil { transitionSupportedTotal = fields["transitionSupportedTotalCount"] }
            #expect(fields["functionCount"] == functionCount)
            #expect(fields["transitionSupportedTotalCount"] == transitionSupportedTotal)
            let batchSelected = fields["selectedCount"] ?? 0
            let batchExact = fields["exactCount"] ?? 0
            let batchStructural = fields["legacyStructuralPhiDefectCount"] ?? 0
            let batchUnclassified = fields["unclassifiedMismatchCount"] ?? 0
            print("dualBatch start=\(batch.lowerBound) end=\(batch.upperBound) selected=\(batchSelected) exact=\(batchExact) structural=\(batchStructural) unclassified=\(batchUnclassified) maximumResidentBytes=\(result.maximumResidentBytes)")
            if (fields["unclassifiedMismatchCount"] ?? 0) > 0 {
                for row in rows where row.hasPrefix("dualLLVM\\t") && row.contains("exact=false") { print("unclassifiedCandidate \(row)") }
                for row in rows where row.hasPrefix("dualCompatibility\\t") && row.contains("legacyStructuralPhiDefect=false") { print("unclassifiedCompatibility \(row)") }
            }
            for key in ["selectedCount", "exactCount", "typedInvalidCount", "legacyStructuralPhiDefectCount", "legacyPlaceholderMismatchCount", "legacyUnwrittenParameterPhiMismatchCount", "unclassifiedMismatchCount", "typedPlaceholderCount", "typedRecordNonzeroCount"] {
                totals[key, default: 0] += fields[key] ?? 0
            }
            for row in rows where row.hasPrefix("dualLLVM\\t") {
                for field in row.components(separatedBy: "\\t") where field.hasPrefix("functionID=") {
                    if let functionID = Int(field.dropFirst("functionID=".count)) { #expect(selectedIDs.insert(functionID).inserted) }
                }
            }
        }
        // Three structurally defective legacy artifacts are covered by the dedicated
        // incompatibility regression. Two legacy record-expansion hot functions are
        // covered by the permanent exact final-artifact oracle. These exact names are
        // resolved to current FunctionIDs only inside this test diagnostic.
        let dedicatedExactCount = 2
        let dedicatedIncompatibilityCount = 3
        #expect(functionCount != nil)
        #expect(functionCount! < 1400)
        #expect(transitionSupportedTotal != nil)
        if requestedStart == 0 && requestedEnd >= functionCount! {
            #expect((totals["selectedCount"] ?? 0) + dedicatedExactCount + dedicatedIncompatibilityCount == transitionSupportedTotal!)
        }
        #expect(selectedIDs.count == totals["selectedCount"])
        #expect(totals["typedInvalidCount"] == 0)
        #expect(totals["typedPlaceholderCount"] == 0)
        #expect(totals["typedRecordNonzeroCount"] == 0)
        let classified = (totals["exactCount"] ?? 0) + (totals["legacyStructuralPhiDefectCount"] ?? 0)
        #expect(classified == totals["selectedCount"])
        #expect(totals["legacyPlaceholderMismatchCount"] == 0)
        #expect(totals["legacyUnwrittenParameterPhiMismatchCount"] == 0)
        #expect(totals["unclassifiedMismatchCount"] == 0)
        #expect(observedMaximumResidentBytes <= 1024 * 1024 * 1024)
        let selectedCount = totals["selectedCount"] ?? 0
        let exactCount = totals["exactCount"] ?? 0
        let structuralCount = totals["legacyStructuralPhiDefectCount"] ?? 0
        print("broadDualAudit requestedStart=\(requestedStart) requestedEnd=\(requestedEnd) functionCount=\(functionCount!) transitionSupported=\(transitionSupportedTotal!) selected=\(selectedCount) dedicatedExact=\(dedicatedExactCount) dedicatedIncompatibility=\(dedicatedIncompatibilityCount) exact=\(exactCount) structural=\(structuralCount) resourceSplits=\(resourceSplitCount) maximumResidentBytes=\(observedMaximumResidentBytes)")
    }

    @Test("Typed MIR refuses an unfrozen MemoryGraph")
    func typedMIRRefusesAnUnfrozenMemoryGraph() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyArenaStats
        function constantValue(): Int {
            return 7
        }

        """
        let first = try runTypedSyntaxFixture(source: fixture, name: "MIRUnfrozenMemoryFirst.range", directory: directory)
        let second = try runTypedSyntaxFixture(source: fixture, name: "MIRUnfrozenMemorySecond.range", directory: directory)
        #expect(first.timedOut == false)
        #expect(first.exitCode == 0)
        #expect(first.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(first.stdout.contains("name=constantValue\\tvalid=true"))
        #expect(first.stdout.contains("mirBeforeMemoryStatus=-1"))
        #expect(first.stdout.contains("memoryStatus=0\\tmemoryValid=true"))
        #expect(first.stdout.contains("mirStatus=0\\tmirValid=true\\tmirValidationCode=0"))
        #expect(first.stdout.contains("functionCount=1"))
        #expect(first.stdout.contains("destroyCount=1"))
    }

    @Test("Canonical MemoryGraph records unique state writes without placement")
    func canonicalMemoryGraphRecordsUniqueStateWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyArenaStats
        function updateState(): Int {
            state value: Int(0)
            value: value + 1
            return value
        }

        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CanonicalStateWrite.range", directory: directory)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("name=updateState\\ttransitionSupported=true\\ttransitionReason=\\tvalid=true"))
        #expect(result.stdout.contains("semanticStatus=0\\tsemanticValid=true"))
        #expect(result.stdout.contains("memoryPlacementFacts=0"))
        #expect(result.stdout.contains("memoryMutableValueFacts=1"))
        #expect(result.stdout.contains("memoryWriteFacts=1"))
    }

    @Test("Canonical MIR versions mutable state through a while phi")
    func canonicalMIRVersionsStateThroughWhilePhi() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyArenaStats
        function countToThree(): Int {
            state value: Int(0)
            while value < 3 {
                value: value + 1
            }
            return value
        }

        """
        let first = try runTypedSyntaxFixture(source: fixture, name: "CanonicalStateWhileMIR.range", directory: directory)
        let second = try runTypedSyntaxFixture(source: fixture, name: "CanonicalStateWhileMIRRepeated.range", directory: directory)
        #expect(first.exitCode == 0)
        #expect(first.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(first.stdout.contains("name=countToThree\\ttransitionSupported=true\\ttransitionReason=\\tvalid=true"))
        #expect(first.stdout.contains("memoryPlacementFacts=0"))
        #expect(first.stdout.contains("memoryWriteFacts=1"))
        #expect(first.stdout.contains("mirStatus=0\\tmirValid=true\\tmirValidationCode=0"))
        #expect(first.stdout.contains("mirPhiOperations=1"))
        #expect(first.stdout.contains("mirAssignVersionOperations=1"))
        #expect(first.stdout.contains("llvmEmissionValid=true"))
        #expect(first.stdout.contains("llvmRecordLength=0"))
    }

    @Test("Canonical state while MIR exactly matches legacy LLVM")
    func canonicalStateWhileMIRExactlyMatchesLegacyLLVM() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualFunction	countToThree
        function countToThree(): Int {
            state value: Int(0)
            while value < 3 {
                value: value + 1
            }
            return value
        }

        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CanonicalStateWhileDualLLVMV2.range", directory: directory)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=1"))
        #expect(result.stdout.contains("name=countToThree\\texact=true\\tcontentEqual=true\\ttypedValid=true"))
        #expect(result.stdout.contains("typedRecordLength=0"))
    }

    @Test("Canonical ordered String comparison semantic MIR and LLVM exactly match legacy")
    func canonicalOrderedStringComparisonMIRExactlyMatchesLegacyLLVM() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualFunction\tstringComesBefore
        function stringComesBefore(left: String, right: String): Bool {
            return left < right
        }

        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CanonicalOrderedStringComparisonDualLLVM.range", directory: directory)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=1"))
        #expect(result.stdout.contains("name=stringComesBefore\\texact=true\\tcontentEqual=true\\ttypedValid=true"))
        #expect(result.stdout.contains("typedRecordLength=0"))
    }

    @Test("Canonical MIR validates the actual validator family")
    func canonicalMIRValidatesActualValidatorFamily() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try repositoryRoot()
        let compilerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"), encoding: .utf8)
        let compilerCoreSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"), encoding: .utf8)
        let lexerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"), encoding: .utf8)
        let fixture = """
        compilerNativeBodyArenaStats
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CompilerActualValidatorMIR.range", directory: directory, timeout: 360)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        for name in ["compilerSemanticGraphIsValid", "compilerMemoryGraphIsValid", "compilerBodyArenaIsValid"] {
            let line = result.stdout.components(separatedBy: "\\n").first { $0.contains("name=\(name)\\t") }
            #expect(line?.contains("memoryValid=true") == true)
            #expect(line?.contains("mirStatus=0\\tmirValid=true\\tmirValidationCode=0") == true)
            #expect(line?.contains("llvmRecordLength=0") == true)
        }
    }

    @Test("Canonical validator MIR classifies legacy-only LLVM defects")
    func canonicalValidatorMIRClassifiesLegacyOnlyLLVMDefects() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try repositoryRoot()
        let compilerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"), encoding: .utf8)
        let compilerCoreSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"), encoding: .utf8)
        let lexerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"), encoding: .utf8)
        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualFunction	compilerSemanticGraphIsValid
        compilerDualFunction	compilerMemoryGraphIsValid
        compilerDualFunction	compilerBodyArenaIsValid
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CompilerActualValidatorLegacyDefects.range", directory: directory, timeout: 360)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=3"))
        for name in ["compilerSemanticGraphIsValid", "compilerMemoryGraphIsValid"] {
            let dual = result.stdout.components(separatedBy: "\\n").first { $0.contains("dualLLVM\\t") && $0.contains("name=\(name)\\t") }
            let compatibility = result.stdout.components(separatedBy: "\\n").first { $0.contains("dualCompatibility\\t") && $0.contains("name=\(name)\\t") }
            #expect(dual?.contains("exact=false") == true)
            #expect(dual?.contains("typedValid=true") == true)
            #expect(dual?.contains("typedRecordLength=0") == true)
            #expect(compatibility?.contains("legacyPlaceholder=false") == true)
            #expect(compatibility?.contains("typedPlaceholder=false") == true)
            #expect(compatibility?.contains("legacyUnwrittenParameterPhi=true") == true)
            #expect(compatibility?.contains("typedUnwrittenParameterPhi=false") == true)
        }
        let bodyDual = result.stdout.components(separatedBy: "\\n").first { $0.contains("dualLLVM\\t") && $0.contains("name=compilerBodyArenaIsValid\\t") }
        let bodyCompatibility = result.stdout.components(separatedBy: "\\n").first { $0.contains("dualCompatibility\\t") && $0.contains("name=compilerBodyArenaIsValid\\t") }
        #expect(bodyDual?.contains("exact=false") == true)
        #expect(bodyDual?.contains("typedValid=true") == true)
        #expect(bodyDual?.contains("typedRecordLength=0") == true)
        #expect(bodyCompatibility?.contains("legacyPlaceholder=true") == true)
        #expect(bodyCompatibility?.contains("typedPlaceholder=false") == true)
    }

    @Test("Canonical dual audit lowers CFG builder exactly with transient reset")
    func canonicalDualAuditLowersCFGBuilderExactlyWithTransientReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try repositoryRoot()
        let compilerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"), encoding: .utf8)
        let compilerCoreSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"), encoding: .utf8)
        let lexerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"), encoding: .utf8)
        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualFunction	compilerBodyArenaBuildCFG
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CompilerBodyArenaBuildCFGLegacyPreflight.range", directory: directory, timeout: 360)
        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=1"))
        #expect(result.stdout.contains("exactCount=1"))
        #expect(result.stdout.contains("legacyStructuralPhiDefectCount=0"))
        #expect(result.stdout.contains("name=compilerBodyArenaBuildCFG\\texact=true\\tcontentEqual=true\\ttypedValid=true"))
        #expect(result.stdout.contains("legacyStructuralPhiDefect=false"))
        #expect(result.stdout.contains("typedPlaceholder=false"))
        #expect(result.stdout.contains("typedRecordLength=0"))
    }

    @Test("Canonical dual preflight exactly partitions semantic and memory functions")
    func canonicalDualPreflightExactlyPartitionsSemanticAndMemoryFunctions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try repositoryRoot()
        let compilerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Compiler.range"), encoding: .utf8)
        let compilerCoreSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/CompilerCore.range"), encoding: .utf8)
        let lexerSource = try String(contentsOf: root.appendingPathComponent("RangeCompiler/Range/Programs/Compiler/Lexer.range"), encoding: .utf8)
        let transitionMarkers = (240...319).map { "compilerDualTransitionFunctionID_\($0)_" }.joined(separator: "\n")
        let fixture = """
        compilerNativeBodyLLVMDualStats
        compilerDualSkipFunction	compilerSemanticGraphIsValid
        \(transitionMarkers)
        \(compilerSource)
        \(compilerCoreSource)
        \(lexerSource)
        """
        let result = try runTypedSyntaxFixture(source: fixture, name: "CompilerSemanticMemoryLegacyPhiPartition.range", directory: directory, timeout: 360)
        #expect(result.timedOut == false)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("selectedCount=60"))
        #expect(result.stdout.contains("exactCount=42"))
        #expect(result.stdout.contains("typedInvalidCount=0"))
        #expect(result.stdout.contains("legacyStructuralPhiDefectCount=18"))
        #expect(result.stdout.contains("legacyPlaceholderMismatchCount=0"))
        #expect(result.stdout.contains("legacyUnwrittenParameterPhiMismatchCount=0"))
        #expect(result.stdout.contains("unclassifiedMismatchCount=0"))
        #expect(result.stdout.contains("typedPlaceholderCount=0"))
        #expect(result.stdout.contains("typedRecordNonzeroCount=0"))
    }

    @Test("Canonical semantics rejects writes through let")
    func canonicalSemanticsRejectsLetWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = """
        compilerNativeBodyArenaStats
        function rejectLetWrite(): Int {
            let value: Int(0)
            value: value + 1
            return value
        }

        """
        let first = try runTypedSyntaxFixture(source: fixture, name: "CanonicalLetWriteFirst.range", directory: directory)
        let second = try runTypedSyntaxFixture(source: fixture, name: "CanonicalLetWriteSecond.range", directory: directory)
        #expect(first.exitCode == 0)
        #expect(first.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(first.stdout.contains("name=rejectLetWrite\\ttransitionSupported=true\\ttransitionReason=\\tvalid=true"))
        #expect(first.stdout.contains("semanticStatus=-1\\tsemanticValid=false"))
    }

    @Test("Opt-in compiler cost metrics report actual selected-function work")
    func optInCompilerCostMetricsReportActualSelectedFunctionWork() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let enabledFixture = """
        compilerNativeSourceSetCostStats
        function compilerSourceFileTableColumnCount(): Int {
            return 5
        }

        function compilerSourceRoleProject(value: Int): Int {
            return value + 1
        }

        """
        let enabled = try runTypedSyntaxFixture(
            source: enabledFixture,
            name: "CompilerCostMetricsEnabled.range",
            directory: directory
        )

        #expect(enabled.timedOut == false)
        #expect(enabled.exitCode == 0)
        #expect(enabled.stderr.isEmpty)
        #expect(enabled.stdout.contains("phase=cost"))
        #expect(enabled.stdout.contains("compilerCostMetrics\tenabled=0"))
        #expect(metricValue(named: "textBufferAppendCalls", in: enabled.stdout) > 0)
        #expect(metricValue(named: "textBufferAppendBytes", in: enabled.stdout) > 0)
        let typedLine = enabled.stdout.split(separator: "\n").first {
            $0.contains("compilerCostFunction") && $0.contains("name=compilerSourceFileTableColumnCount")
        }
        let legacyLine = enabled.stdout.split(separator: "\n").first {
            $0.contains("compilerCostFunction") && $0.contains("name=compilerSourceRoleProject")
        }
        #expect(typedLine?.contains("legacyParses=0") == true)
        #expect(typedLine?.contains("recordBytes=0") == true)
        #expect(legacyLine?.contains("legacyParses=1") == true)
        #expect(metricValue(named: "recordBytes", in: String(legacyLine ?? "")) > 0)
        let enabledSecond = try runTypedSyntaxFixture(
            source: enabledFixture,
            name: "CompilerCostMetricsEnabledSecond.range",
            directory: directory
        )
        #expect(enabledSecond.exitCode == 0)
        #expect(enabledSecond.stderr.isEmpty)
        #expect(enabled.stdout == enabledSecond.stdout)

        let disabledFixture = enabledFixture.replacingOccurrences(
            of: "compilerNativeSourceSetCostStats",
            with: "compilerNativeSourceSetLLVMText"
        )
        let disabledFirst = try runTypedSyntaxFixture(
            source: disabledFixture,
            name: "CompilerCostMetricsDisabledFirst.range",
            directory: directory
        )
        let disabledSecond = try runTypedSyntaxFixture(
            source: disabledFixture,
            name: "CompilerCostMetricsDisabledSecond.range",
            directory: directory
        )
        #expect(disabledFirst.exitCode == 0)
        #expect(disabledFirst.stderr.isEmpty)
        #expect(disabledFirst.stdout == disabledSecond.stdout)
        #expect(!disabledFirst.stdout.contains("compilerCostMetrics"))
        #expect(!disabledFirst.stdout.contains("compilerCostFunction"))
        #expect(!disabledFirst.stdout.contains("compilerMetricsReset"))
    }

    @Test("Shared compiler metrics runtime counts controlled operations only when enabled")
    func sharedCompilerMetricsRuntimeCountsControlledOperationsOnlyWhenEnabled() throws {
        let root = try repositoryRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = directory.appendingPathComponent("CompilerMetricsHarness.c")
        let executable = directory.appendingPathComponent("CompilerMetricsHarness")
        try """
        #include <stdbool.h>
        #include <stdint.h>
        #include <stdio.h>
        int32_t compilerMetricsReset(void);
        int32_t compilerMetricsSetEnabled(bool enabled);
        char *compilerMetricsReport(void);
        char *stringConcat(char *left, char *right);
        char *stringSubstring(char *value, int32_t start, int32_t end);
        void *rangeConstructCreate(char *name);
        void *rangeConstructSetInt(void *object, char *name, int32_t value);
        int32_t rangeConstructGetInt(void *object, char *name);
        void *textBufferCreate(int32_t capacity);
        int32_t textBufferAppend(void *buffer, char *text);
        char *textBufferMaterialize(void *buffer);
        int32_t textBufferDestroy(void *buffer);
        int main(void) {
            compilerMetricsReset();
            compilerMetricsSetEnabled(true);
            char *joined = stringConcat("ab", "cd");
            stringSubstring(joined, 1, 3);
            void *object = rangeConstructCreate("Probe");
            rangeConstructSetInt(object, "value", 7);
            rangeConstructGetInt(object, "value");
            void *buffer = textBufferCreate(1);
            textBufferAppend(buffer, "hello");
            textBufferMaterialize(buffer);
            textBufferDestroy(buffer);
            compilerMetricsSetEnabled(false);
            stringConcat("ignored", "work");
            void *ignoredObject = rangeConstructCreate("Ignored");
            rangeConstructSetInt(ignoredObject, "field", 1);
            rangeConstructGetInt(ignoredObject, "field");
            void *ignoredBuffer = textBufferCreate(1);
            textBufferAppend(ignoredBuffer, "ignored");
            textBufferMaterialize(ignoredBuffer);
            textBufferDestroy(ignoredBuffer);
            puts(compilerMetricsReport());
            return 0;
        }
        """.write(to: harness, atomically: true, encoding: .utf8)
        let runtime = root.appendingPathComponent("RangeCompiler/Runtime")
        let compile = try runCapturedProcess(
            executable: "/usr/bin/clang",
            arguments: [
                harness.path,
                runtime.appendingPathComponent("RangeCompilerHost.c").path,
                runtime.appendingPathComponent("RangeCompilerMetrics.c").path,
                runtime.appendingPathComponent("RangeString.c").path,
                runtime.appendingPathComponent("RangeTextBuffer.c").path,
                "-o", executable.path,
            ]
        )
        #expect(compile.exitCode == 0)
        #expect(compile.stderr.isEmpty)
        let enabled = try runCapturedProcess(executable: executable.path, arguments: [])
        #expect(enabled.exitCode == 0)
        #expect(enabled.stderr.isEmpty)
        #expect(metricValue(named: "stringConcatCalls", in: enabled.stdout) == 1)
        #expect(metricValue(named: "stringConcatBytes", in: enabled.stdout) == 4)
        #expect(metricValue(named: "stringSubstringCalls", in: enabled.stdout) == 1)
        #expect(metricValue(named: "stringSubstringSourceBytes", in: enabled.stdout) == 4)
        #expect(metricValue(named: "stringSubstringResultBytes", in: enabled.stdout) == 2)
        #expect(metricValue(named: "constructObjects", in: enabled.stdout) == 1)
        #expect(metricValue(named: "constructFields", in: enabled.stdout) == 1)
        #expect(metricValue(named: "constructNameBytes", in: enabled.stdout) == 10)
        #expect(metricValue(named: "constructGetProbes", in: enabled.stdout) == 1)
        #expect(metricValue(named: "textBufferAppendCalls", in: enabled.stdout) == 1)
        #expect(metricValue(named: "textBufferAppendBytes", in: enabled.stdout) == 5)
        #expect(metricValue(named: "textBufferMaterializeCalls", in: enabled.stdout) == 1)
        #expect(metricValue(named: "textBufferMaterializeBytes", in: enabled.stdout) == 5)
        #expect(metricValue(named: "textBufferReallocations", in: enabled.stdout) == 1)
        #expect(metricValue(named: "textBufferReallocationBytes", in: enabled.stdout) == 0)
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

private func runTypedSyntaxFixture(
    source: String,
    name: String,
    directory: URL,
    timeout: TimeInterval = 120
) throws -> ScriptResult {
    let sourceURL = directory.appendingPathComponent(name)
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    let compiler = try repositoryRoot()
        .appendingPathComponent("RangeCompiler/Range/Programs/Compiler", isDirectory: true)
    let executable = try TypedSyntaxCompilerCache.shared.executable(for: compiler)
    return try runFixtureExecutable(executable: executable, source: sourceURL, timeout: timeout)
}

private func opaqueIntBufferFixture(body: String, includeCount: Bool = false) -> String {
    let countDeclaration = includeCount ? """
        @language
        function intBufferCount(buffer: IntBuffer): Int
        """ : ""
    return """
    compilerMemoryGraph
    @language
    construct IntBuffer {}
    @language
    function intBufferCreate(capacity: Int): IntBuffer
    @language
    function intBufferDestroy(buffer: IntBuffer): Int
    \(countDeclaration)
    @main {
    \(body)
    }

    """
}

private func runOpaqueIntBufferFailureFixture(body: String, name: String, includeCount: Bool = false) throws -> ScriptResult {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = try runTypedSyntaxFixture(
        source: opaqueIntBufferFixture(body: body, includeCount: includeCount),
        name: name,
        directory: directory
    )
    #expect(result.timedOut == false)
    #expect(result.stderr.isEmpty)
    return result
}

private final class TypedSyntaxCompilerCache: @unchecked Sendable {
    static let shared = TypedSyntaxCompilerCache()

    private let lock = NSLock()
    private var cachedFingerprint: String?
    private var cachedExecutable: URL?

    func executable(for compilerDirectory: URL) throws -> URL {
        let root = try repositoryRoot()
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: compilerDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "range" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let toolInputs = try typedSyntaxCompilerToolInputs(root: root)
        let clangVersion = try runCapturedProcess(
            executable: "/usr/bin/env",
            arguments: ["clang", "--version"]
        )
        guard clangVersion.exitCode == 0 else {
            throw RangeScriptTestError.typedFixtureCompilerFailed(
                clangVersion.stdout,
                clangVersion.stderr
            )
        }
        let fingerprint = try typedSyntaxCompilerFingerprint(
            files: sourceFiles + toolInputs,
            context: "typed-fixture-cache-v2\n\(ProcessInfo.processInfo.operatingSystemVersionString)\n\(clangVersion.stdout)\n\(clangVersion.stderr)"
        )

        lock.lock()
        defer { lock.unlock() }
        if cachedFingerprint == fingerprint,
            let cachedExecutable,
            FileManager.default.isExecutableFile(atPath: cachedExecutable.path)
        {
            return cachedExecutable
        }

        let cacheParent = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RangeCompilerTests", isDirectory: true)
            .appendingPathComponent("typed-fixture-v2", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheParent, withIntermediateDirectories: true)
        let cacheRoot = cacheParent.appendingPathComponent(fingerprint, isDirectory: true)
        let executable = cacheRoot.appendingPathComponent("Compiler/.range/Build/llvm/Compiler")
        let ready = cacheRoot.appendingPathComponent("READY")
        let lockURL = cacheParent.appendingPathComponent("\(fingerprint).lock")
        try withTypedFixtureCacheLock(lockURL: lockURL) {
            if typedFixtureCacheIsReady(executable: executable, ready: ready, fingerprint: fingerprint) {
                return
            }
            try? FileManager.default.removeItem(at: cacheRoot)
            let buildRoot = cacheParent.appendingPathComponent(
                "\(fingerprint).build.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: buildRoot) }
            let mirroredCompiler = buildRoot.appendingPathComponent("Compiler", isDirectory: true)
            try FileManager.default.createDirectory(at: mirroredCompiler, withIntermediateDirectories: true)
            for sourceFile in sourceFiles {
                try FileManager.default.copyItem(
                    at: sourceFile,
                    to: mirroredCompiler.appendingPathComponent(sourceFile.lastPathComponent)
                )
            }
            let build = try runRangeScript(
                arguments: ["compile-executable", mirroredCompiler.path],
                timeout: 180
            )
            guard !build.timedOut, build.exitCode == 0, build.stderr.isEmpty else {
                throw RangeScriptTestError.typedFixtureCompilerFailed(build.stdout, build.stderr)
            }
            let builtExecutable = mirroredCompiler
                .appendingPathComponent(".range/Build/llvm/Compiler")
            guard FileManager.default.isExecutableFile(atPath: builtExecutable.path) else {
                throw RangeScriptTestError.typedFixtureCompilerMissing(builtExecutable.path)
            }
            try "\(fingerprint)\n".write(
                to: buildRoot.appendingPathComponent("READY"),
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.moveItem(at: buildRoot, to: cacheRoot)
        }
        guard typedFixtureCacheIsReady(executable: executable, ready: ready, fingerprint: fingerprint) else {
            throw RangeScriptTestError.typedFixtureCompilerMissing(executable.path)
        }
        cachedFingerprint = fingerprint
        cachedExecutable = executable
        return executable
    }
}

private func typedSyntaxCompilerToolInputs(root: URL) throws -> [URL] {
    var inputs = [
        root.appendingPathComponent("scripts/range"),
        root.appendingPathComponent("RangeCompiler/Package.swift"),
        root.appendingPathComponent("RangeCompiler/Runtime/RangeCompilerHost.c"),
        root.appendingPathComponent("RangeCompiler/Runtime/RangeCompilerMetrics.c"),
        root.appendingPathComponent("RangeCompiler/Runtime/RangeTextBuffer.c"),
        root.appendingPathComponent("RangeCompiler/Runtime/RangeIntBuffer.c"),
        root.appendingPathComponent("RangeCompiler/Runtime/RangeString.c"),
    ]
    let coreSources = root.appendingPathComponent("RangeCompiler/Range/Core", isDirectory: true)
    let coreEnumerator = FileManager.default.enumerator(
        at: coreSources,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    while let file = coreEnumerator?.nextObject() as? URL {
        if file.pathExtension == "range" { inputs.append(file) }
    }
    let sources = root.appendingPathComponent("RangeCompiler/Sources", isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: sources,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    while let file = enumerator?.nextObject() as? URL {
        if file.pathExtension == "swift" { inputs.append(file) }
    }
    return inputs.sorted { $0.path < $1.path }
}

private func metricValue(named name: String, in text: String) -> Int {
    guard let range = text.range(of: "\(name)=") else { return -1 }
    let suffix = text[range.upperBound...]
    let digits = suffix.prefix { $0.isNumber }
    return Int(digits) ?? -1
}

private func typedSyntaxCompilerFingerprint(files: [URL], context: String) throws -> String {
    var hash = SHA256()
    hash.update(data: Data(context.utf8))
    for file in files.sorted(by: { $0.path < $1.path }) {
        let path = Data(file.path.utf8)
        withUnsafeBytes(of: UInt64(path.count).littleEndian) { hash.update(bufferPointer: $0) }
        hash.update(data: path)
        let contents = try Data(contentsOf: file, options: [.mappedIfSafe])
        withUnsafeBytes(of: UInt64(contents.count).littleEndian) { hash.update(bufferPointer: $0) }
        hash.update(data: contents)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

private func typedFixtureCacheIsReady(executable: URL, ready: URL, fingerprint: String) -> Bool {
    guard FileManager.default.isExecutableFile(atPath: executable.path),
        let marker = try? String(contentsOf: ready, encoding: .utf8)
    else { return false }
    return marker == "\(fingerprint)\n"
}

private func withTypedFixtureCacheLock(lockURL: URL, body: () throws -> Void) throws {
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
        throw RangeScriptTestError.typedFixtureCacheLockFailed(lockURL.path)
    }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else {
        throw RangeScriptTestError.typedFixtureCacheLockFailed(lockURL.path)
    }
    defer { flock(descriptor, LOCK_UN) }
    try body()
}

private func runFixtureExecutable(
    executable: URL,
    source: URL,
    timeout: TimeInterval,
    maximumResidentBytes: UInt64? = nil
) throws -> ScriptResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = [source.path]

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
    var observedMaximumResidentBytes: UInt64 = 0
    var resourceLimited = false
    while process.isRunning, Date() < deadline, !resourceLimited {
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        if proc_pidinfo(process.processIdentifier, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize) == taskInfoSize {
            observedMaximumResidentBytes = max(observedMaximumResidentBytes, taskInfo.pti_resident_size)
            if let maximumResidentBytes, observedMaximumResidentBytes > maximumResidentBytes { resourceLimited = true }
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    let timedOut = process.isRunning && !resourceLimited
    if timedOut || resourceLimited { process.terminate() }
    process.waitUntilExit()
    try? stdoutHandle.close()
    try? stderrHandle.close()
    return ScriptResult(
        exitCode: process.terminationStatus,
        stdout: (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? "",
        stderr: (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? "",
        timedOut: timedOut,
        maximumResidentBytes: observedMaximumResidentBytes,
        resourceLimited: resourceLimited
    )
}

private func typedSyntaxDeclarationFingerprint(in output: String, name: String) -> String? {
    let nameField = "name=\(name)"
    for line in output.split(separator: "\n") {
        let fields = line.split(separator: "\t")
        guard fields.first == "declaration",
            fields.contains(where: { $0 == Substring(nameField) })
        else {
            continue
        }
        guard let fingerprint = fields.first(where: { $0.hasPrefix("fingerprint=") }) else {
            return nil
        }
        return String(fingerprint.dropFirst("fingerprint=".count))
    }
    return nil
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
        timedOut: timedOut,
        maximumResidentBytes: 0,
        resourceLimited: false
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
        timedOut: false,
        maximumResidentBytes: 0,
        resourceLimited: false
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
    var maximumResidentBytes: UInt64
    var resourceLimited: Bool
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
    case typedFixtureCacheLockFailed(String)
    case typedFixtureCompilerFailed(String, String)
    case typedFixtureCompilerMissing(String)
}
