import Darwin
import Foundation
import RangeCompiler
import RangeEmission

public struct SwiftBootstrapError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct SwiftBootstrapCompiler {
    private let phaseMetrics = PhaseMetrics()

    public init() {}

    @discardableResult
    public func compileExecutable(rangeRoot: URL, input: URL) throws -> URL {
        let layout = try executableLayout(for: input)

        try? FileManager.default.removeItem(at: layout.buildRoot)
        try FileManager.default.createDirectory(
            at: layout.buildRoot,
            withIntermediateDirectories: true
        )

        try emitLLVM(rangeRoot: rangeRoot, input: input, output: layout.llvmIR)
        try linkExecutable(
            llvmIR: layout.llvmIR,
            additionalInputs: coreRuntimeSupportPaths(rangeRoot: rangeRoot),
            executable: layout.executable
        )
        return layout.executable
    }

    @discardableResult
    public func run(rangeRoot: URL, input: URL, arguments: [String]) throws -> Int32 {
        let executable = try compileExecutable(rangeRoot: rangeRoot, input: input)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @discardableResult
    public func checkBootstrapCompiler(rangeRoot: URL, compilerDirectory: URL) throws -> URL {
        let executable = try compileExecutable(rangeRoot: rangeRoot, input: compilerDirectory)
        let mainInput = compilerDirectory.appendingPathComponent("Main.range")
        let mainResult = try runExecutable(executable: executable, arguments: [mainInput.path], stdin: nil)
        guard mainResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler exited \(mainResult.exitCode): \(mainInput.path)
                --- stdout ---
                \(prefixLines(mainResult.stdout))
                --- stderr ---
                \(prefixLines(mainResult.stderr))
                """
            )
        }
        guard mainResult.stdout.contains("macroAttribute\\t@main"),
            mainResult.stdout.contains("identifier\\tcommandLineArgumentCount"),
            mainResult.stdout.contains("keyword\\treturn"),
            mainResult.stdout.contains("ast\\tmainBlock"),
            mainResult.stdout.contains("ast\\tstatement\\tkind=return\\texpression=integerLiteral(0)"),
            mainResult.stdout.contains("compilerCoreLLVM\\tmain"),
            mainResult.stdout.contains("compilerCoreLLVMText\\t"),
            mainResult.stdout.contains("declare i32 @puts(ptr)"),
            mainResult.stdout.contains("define i32 @main()")
        else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler did not scan expected entrypoint tokens: \(mainInput.path)
                --- stdout ---
                \(prefixLines(mainResult.stdout))
                --- stderr ---
                \(prefixLines(mainResult.stderr))
                """
            )
        }

        let lexerInput = compilerDirectory.appendingPathComponent("Lexer.range")
        let lexerResult = try runExecutable(executable: executable, arguments: [lexerInput.path], stdin: nil)
        guard lexerResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler exited \(lexerResult.exitCode): \(lexerInput.path)
                --- stdout ---
                \(prefixLines(lexerResult.stdout))
                --- stderr ---
                \(prefixLines(lexerResult.stderr))
                """
            )
        }
        guard lexerResult.stdout.contains("keyword\\tconstruct"),
            lexerResult.stdout.contains("identifier\\tRangeLexedToken"),
            lexerResult.stdout.contains("identifier\\tlexNextRangeToken"),
            lexerResult.stdout.contains("stringLiteral\\t\"ellipsis\""),
            lexerResult.stdout.contains("ast\\tfunction\\tname=lexRangeSource"),
            lexerResult.stdout.contains("ast\\tfunction\\tname=rangeToken"),
            lexerResult.stdout.contains("ast\\tfunction\\tname=hasRangePrefix")
        else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler did not scan expected lexer tokens: \(lexerInput.path)
                --- stdout ---
                \(prefixLines(lexerResult.stdout))
                --- stderr ---
                \(prefixLines(lexerResult.stderr))
                """
            )
        }

        let compilerCoreInput = compilerDirectory.appendingPathComponent("CompilerCore.range")
        let compilerCoreResult = try runExecutable(executable: executable, arguments: [compilerCoreInput.path], stdin: nil)
        guard compilerCoreResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler exited \(compilerCoreResult.exitCode): \(compilerCoreInput.path)
                --- stdout ---
                \(prefixLines(compilerCoreResult.stdout))
                --- stderr ---
                \(prefixLines(compilerCoreResult.stderr))
                """
            )
        }
        guard compilerCoreResult.stdout.contains("ast\\tfunction\\tname=compilerCoreASTSummary"),
            compilerCoreResult.stdout.contains("ast\\tfunction\\tname=compilerCoreLLVM"),
            compilerCoreResult.stdout.contains("ast\\tfunction\\tname=compilerCoreMainLLVM")
        else {
            throw SwiftBootstrapError(
                """
                Bootstrap compiler did not parse expected compiler-core declarations: \(compilerCoreInput.path)
                --- stdout ---
                \(prefixLines(compilerCoreResult.stdout))
                --- stderr ---
                \(prefixLines(compilerCoreResult.stderr))
                """
            )
        }
        print("Bootstrap compiler check succeeded: \(executable.path)")
        return executable
    }

    @discardableResult
    public func checkStage1Compiler(rangeRoot: URL, compilerDirectory: URL) throws -> URL {
        let executable = try compileExecutable(rangeRoot: rangeRoot, input: compilerDirectory)
        let sourceBundle = try stage1CompilerSourceBundle(
            compilerDirectory: compilerDirectory,
            directive: "compilerSourceInventory"
        )
        defer {
            try? FileManager.default.removeItem(at: sourceBundle.deletingLastPathComponent())
        }

        let result = try runExecutable(executable: executable, arguments: [sourceBundle.path], stdin: nil)
        guard result.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler inventory check exited \(result.exitCode): \(sourceBundle.path)
                --- stdout ---
                \(prefixLines(result.stdout))
                --- stderr ---
                \(prefixLines(result.stderr))
                """
            )
        }

        guard result.stdout.contains("sourceInventory\\tprogram"),
            result.stdout.contains("sourceFile\\tindex=0\\trole=project\\tpath=Compiler.range"),
            result.stdout.contains("sourceFile\\tindex=1\\trole=project\\tpath=CompilerCore.range"),
            result.stdout.contains("sourceFile\\tindex=2\\trole=project\\tpath=Lexer.range"),
            result.stdout.contains("sourceFile\\tindex=3\\trole=project\\tpath=Main.range"),
            result.stdout.contains("sourceFileCount\\t4")
        else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler did not emit expected source inventory: \(sourceBundle.path)
                --- stdout ---
                \(prefixLines(result.stdout))
                --- stderr ---
                \(prefixLines(result.stderr))
                """
            )
        }

        let astBundle = try stage1CompilerSourceBundle(
            compilerDirectory: compilerDirectory,
            directive: "compilerSourceSetAST"
        )
        defer {
            try? FileManager.default.removeItem(at: astBundle.deletingLastPathComponent())
        }

        let astResult = try runExecutable(executable: executable, arguments: [astBundle.path], stdin: nil)
        guard astResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler AST check exited \(astResult.exitCode): \(astBundle.path)
                --- stdout ---
                \(prefixLines(astResult.stdout))
                --- stderr ---
                \(prefixLines(astResult.stderr))
                """
            )
        }

        guard astResult.stdout.contains("sourceSetAST\\tprogram"),
            astResult.stdout.contains("sourceFileAST\\tindex=0\\tpath=Compiler.range"),
            astResult.stdout.contains("sourceFileAST\\tindex=1\\tpath=CompilerCore.range"),
            astResult.stdout.contains("sourceFileAST\\tindex=2\\tpath=Lexer.range"),
            astResult.stdout.contains("sourceFileAST\\tindex=3\\tpath=Main.range\\thasMainBlock=true"),
            astResult.stdout.contains("ast\\tfunction\\tname=compileRangeSource"),
            astResult.stdout.contains("ast\\tfunction\\tname=parseCompilerProgram"),
            astResult.stdout.contains("ast\\tfunction\\tname=lexRangeSource"),
            astResult.stdout.contains("sourceFileASTCount\\t4")
        else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler did not emit expected source-set AST: \(astBundle.path)
                --- stdout ---
                \(prefixLines(astResult.stdout))
                --- stderr ---
                \(prefixLines(astResult.stderr))
                """
            )
        }

        let typesBundle = try stage1CompilerSourceBundle(
            compilerDirectory: compilerDirectory,
            directive: "compilerSourceSetTypes"
        )
        defer {
            try? FileManager.default.removeItem(at: typesBundle.deletingLastPathComponent())
        }

        let typesResult = try runExecutable(executable: executable, arguments: [typesBundle.path], stdin: nil)
        guard typesResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler type check exited \(typesResult.exitCode): \(typesBundle.path)
                --- stdout ---
                \(prefixLines(typesResult.stdout))
                --- stderr ---
                \(prefixLines(typesResult.stderr))
                """
            )
        }

        guard typesResult.stdout.contains("sourceSetTypes\\tprogram"),
            typesResult.stdout.contains("sourceFileTypes\\tindex=0\\tpath=Compiler.range"),
            typesResult.stdout.contains("sourceFileTypes\\tindex=1\\tpath=CompilerCore.range"),
            typesResult.stdout.contains("sourceFileTypes\\tindex=2\\tpath=Lexer.range"),
            typesResult.stdout.contains("sourceFileTypes\\tindex=3\\tpath=Main.range"),
            typesResult.stdout.contains("symbol\\tkind=function\\tname=compileRangeSource"),
            typesResult.stdout.contains("symbol\\tkind=function\\tname=parseCompilerProgram"),
            typesResult.stdout.contains("symbol\\tkind=function\\tname=lexRangeSource"),
            typesResult.stdout.contains("type\\tkind=return\\tscope=main\\tinferred=Int\\tdeclared=Int\\tstatus=ok"),
            typesResult.stdout.contains("sourceFileTypesCount\\t4")
        else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler did not emit expected source-set types: \(typesBundle.path)
                --- stdout ---
                \(prefixLines(typesResult.stdout))
                --- stderr ---
                \(prefixLines(typesResult.stderr))
                """
            )
        }

        let llvmBundle = try stage1CompilerSourceBundle(
            compilerDirectory: compilerDirectory,
            directive: "compilerSourceSetLLVM"
        )
        defer {
            try? FileManager.default.removeItem(at: llvmBundle.deletingLastPathComponent())
        }

        let llvmResult = try runExecutable(executable: executable, arguments: [llvmBundle.path], stdin: nil)
        guard llvmResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler LLVM check exited \(llvmResult.exitCode): \(llvmBundle.path)
                --- stdout ---
                \(prefixLines(llvmResult.stdout))
                --- stderr ---
                \(prefixLines(llvmResult.stderr))
                """
            )
        }

        guard llvmResult.stdout.contains("sourceSetLLVM\\tprogram"),
            llvmResult.stdout.contains("sourceFileLLVM\\tindex=3\\tpath=Main.range\\thasMainBlock=true"),
            llvmResult.stdout.contains("sourceFileLLVMText\\tpath=Main.range"),
            llvmResult.stdout.contains("sourceSetLLVMProgram\\thasMainBlock=true"),
            llvmResult.stdout.contains("sourceFileLLVMCount\\t4")
        else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler did not emit expected source-set LLVM report: \(llvmBundle.path)
                --- stdout ---
                \(prefixLines(llvmResult.stdout))
                --- stderr ---
                \(prefixLines(llvmResult.stderr))
                """
            )
        }

        let loweringAuditText = try runStageCompilerSourceSetDirective(
            executable: executable,
            compilerDirectory: compilerDirectory,
            directive: "compilerNativeSourceSetSelectedScanStats",
            label: "Stage 1 reachable lowering audit"
        )
        guard loweringAuditText.contains("nativeSourceSetStats\\tphase=selectedScan"),
            loweringAuditText.contains("selectedCount="),
            loweringAuditText.contains("lowerableCount="),
            loweringAuditText.contains("excludedCount=0"),
            loweringAuditText.contains("placeholderCount=0")
        else {
            throw SwiftBootstrapError(
                """
                Stage 1 compiler did not emit the expected reachable-lowering audit.
                --- stdout ---
                \(prefixLines(loweringAuditText))
                """
            )
        }

        print("Stage 1 compiler source-set check succeeded: \(executable.path)")
        return executable
    }

    @discardableResult
    public func checkStage2Compiler(rangeRoot: URL, compilerDirectory: URL) throws -> URL {
        let stage1Executable = try measurePhase("stage1-build") {
            try compileExecutable(rangeRoot: rangeRoot, input: compilerDirectory)
        }

        let inventoryText = try measurePhase("stage1-inventory") { try runStageCompilerSourceSetDirective(
            executable: stage1Executable,
            compilerDirectory: compilerDirectory,
            directive: "compilerSourceInventory",
            label: "Stage 2 inventory"
        ) }
        guard inventoryText.contains("sourceInventory\\tprogram"),
            inventoryText.contains("sourceFileCount\\t4")
        else {
            throw SwiftBootstrapError(
                """
                Stage 2 candidate did not preserve source inventory shape.
                --- stdout ---
                \(prefixLines(inventoryText))
                """
            )
        }

        let llvmText = try measurePhase("stage2-llvm-emit") { try runStageCompilerNativeLLVMText(
            executable: stage1Executable,
            compilerDirectory: compilerDirectory,
            label: "Stage 2 LLVM text"
        ) }
        guard !llvmText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SwiftBootstrapError(
                """
                Stage 2 candidate did not emit LLVM text.
                --- materialized stdout ---
                \(prefixLines(llvmText))
                """
            )
        }

        let candidate = stage2CandidateLLVMPath(compilerDirectory: compilerDirectory)
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try llvmText.write(to: candidate, atomically: true, encoding: .utf8)
        let runtimeSupport = compilerHostRuntimeSupportPath(rangeRoot: rangeRoot)
        let runtimeInputs = [runtimeSupport] + coreRuntimeSupportPaths(rangeRoot: rangeRoot)
        let executable = stage2CandidateExecutablePath(compilerDirectory: compilerDirectory)
        try measurePhase("stage2-validate-link") {
            try validateLLVMIR(llvmIR: candidate)
            try linkExecutable(
                llvmIR: candidate,
                additionalInputs: runtimeInputs,
                executable: executable
            )
        }
        let stage2InventoryText = try measurePhase("stage2-linked-inventory") { try runStageCompilerSourceSetDirective(
            executable: executable,
            compilerDirectory: compilerDirectory,
            directive: "compilerSourceInventory",
            label: "Linked Stage 2 inventory"
        ) }
        guard stage2InventoryText.contains("sourceInventory\\tprogram"),
            stage2InventoryText.contains("sourceFile\\tindex=0\\trole=project\\tpath=Compiler.range"),
            stage2InventoryText.contains("sourceFile\\tindex=1\\trole=project\\tpath=CompilerCore.range"),
            stage2InventoryText.contains("sourceFile\\tindex=2\\trole=project\\tpath=Lexer.range"),
            stage2InventoryText.contains("sourceFile\\tindex=3\\trole=project\\tpath=Main.range"),
            stage2InventoryText.contains("sourceFileCount\\t4")
        else {
            throw SwiftBootstrapError(
                """
                Linked Stage 2 compiler did not preserve source inventory.
                --- stdout ---
                \(prefixLines(stage2InventoryText))
                """
            )
        }

        try measurePhase("stage2-linked-smoke") {
            try checkLinkedStage2NormalCompile(
                executable: executable,
                runtimeInputs: runtimeInputs,
                compilerDirectory: compilerDirectory
            )
        }
        let stage3Candidate = try measurePhase("stage3-self-rebuild") {
            try checkLinkedStage2SelfRebuild(
                executable: executable,
                stage2LLVM: candidate,
                runtimeInputs: runtimeInputs,
                compilerDirectory: compilerDirectory
            )
        }

        print("Stage 2 compiler candidate LLVM emitted: \(candidate.path)")
        print("Stage 2 compiler candidate linked: \(executable.path)")
        print("Linked Stage 2 compiler inventory check succeeded: \(executable.path)")
        print("Linked Stage 2 compiler normal compile check succeeded: \(executable.path)")
        print("Stage 3 compiler candidate LLVM emitted: \(stage3Candidate.path)")
        print("Stage 3 compiler candidate linked: \(stage3Candidate.deletingPathExtension().path)")
        print("Linked Stage 2 compiler self-rebuild check succeeded: \(stage3Candidate.path)")
        return candidate
    }

    @discardableResult
    public func checkLLVMRuns(
        rangeRoot: URL,
        manifest: URL,
        requireFullCoverage: Bool
    ) throws -> Int {
        let manifestEntries = try parseRunManifest(manifest)
        if manifestEntries.isEmpty {
            throw SwiftBootstrapError("LLVM run manifest has no runnable entries: \(manifest.path)")
        }

        try validateManifestCoverage(
            entries: manifestEntries,
            manifest: manifest,
            requireFullCoverage: requireFullCoverage
        )

        var count = 0
        for entry in manifestEntries {
            count += 1
            print("[\(count)] run \(entry.source.lastPathComponent)")
            let executable = try compileExecutable(rangeRoot: rangeRoot, input: entry.source)
            let result = try runExecutable(
                executable: executable,
                arguments: entry.arguments,
                stdin: entry.stdin
            )

            if result.exitCode != entry.expectedExit {
                throw SwiftBootstrapError(
                    """
                    Expected exit \(entry.expectedExit), got \(result.exitCode) for \(entry.source.path)
                    --- stdout ---
                    \(prefixLines(result.stdout))
                    --- stderr ---
                    \(prefixLines(result.stderr))
                    """
                )
            }

            if let expectedStdout = entry.expectedStdout, result.stdout != expectedStdout {
                throw SwiftBootstrapError(
                    """
                    Stdout mismatch for \(entry.source.path)
                    --- expected stdout ---
                    \(prefixLines(expectedStdout))
                    --- actual stdout ---
                    \(prefixLines(result.stdout))
                    --- stderr ---
                    \(prefixLines(result.stderr))
                    """
                )
            }
        }

        print("LLVM run checks succeeded for \(count) example(s).")
        return count
    }

    @discardableResult
    public func checkLLVMExamples(rangeRoot: URL, examplesDirectory: URL) throws -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: examplesDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SwiftBootstrapError("Missing LLVM examples directory: \(examplesDirectory.path)")
        }

        let examples = try topLevelRangeFiles(in: examplesDirectory)
        if examples.isEmpty {
            throw SwiftBootstrapError("No LLVM examples found in: \(examplesDirectory.path)")
        }

        let buildRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-llvm-examples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: buildRoot)
        }

        for (index, input) in examples.enumerated() {
            let count = index + 1
            let output = buildRoot
                .appendingPathComponent(input.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("ll")
            print("[\(count)] emit \(input.lastPathComponent)")
            try emitLLVM(rangeRoot: rangeRoot, input: input, output: output)
        }

        print("LLVM emission succeeded for \(examples.count) example(s).")
        return examples.count
    }

    public func emitLLVM(rangeRoot: URL, input: URL, output: URL) throws {
        let inputs = try coreInputs(rangeRoot: rangeRoot) + projectInputs(input: input)
        let program = try CompilerPipeline().buildValidated(inputs: inputs)
        let module = try LLVMModuleEmitter().emit(program: program)

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try module.write(to: output, atomically: true, encoding: .utf8)
    }

    private func rangeFiles(in root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw SwiftBootstrapError("Missing directory: \(root.path)")
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                switch url.lastPathComponent {
                case ".build", ".git", ".range":
                    enumerator.skipDescendants()
                default:
                    break
                }
                continue
            }

            guard url.pathExtension.lowercased() == "range" else {
                continue
            }
            files.append(url)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func topLevelRangeFiles(in directory: URL) throws -> [URL] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw SwiftBootstrapError("Missing directory: \(directory.path)")
        }

        return try urls.filter { url in
            let isRegularFile =
                try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
            return isRegularFile && url.pathExtension.lowercased() == "range"
        }
        .sorted { $0.path < $1.path }
    }

    private func stage1CompilerSourceBundle(compilerDirectory: URL, directive: String) throws -> URL {
        let files = try topLevelRangeFiles(in: compilerDirectory)
        if files.isEmpty {
            throw SwiftBootstrapError("No compiler source files found in: \(compilerDirectory.path)")
        }

        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-stage1-compiler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)

        let bundle = bundleRoot.appendingPathComponent("RangeCompilerSourceSet.range")
        var text = "\(directive)\n"
        for file in files {
            text += "compilerSourceFile\\t\(file.lastPathComponent)\n"
            text += try String(contentsOf: file, encoding: .utf8)
            if !text.hasSuffix("\n") {
                text += "\n"
            }
        }

        try text.write(to: bundle, atomically: true, encoding: .utf8)
        return bundle
    }

    private func runStageCompilerSourceSetDirective(
        executable: URL,
        compilerDirectory: URL,
        directive: String,
        label: String
    ) throws -> String {
        let bundle = try stage1CompilerSourceBundle(
            compilerDirectory: compilerDirectory,
            directive: directive
        )

        let result = try runExecutable(executable: executable, arguments: [bundle.path], stdin: nil)
        guard result.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                \(label) check exited \(result.exitCode): \(bundle.path)
                --- stdout ---
                \(prefixLines(result.stdout))
                --- stderr ---
                \(prefixLines(result.stderr))
                """
            )
        }
        try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent())
        return result.stdout
    }

    private func runStageCompilerNativeLLVMText(
        executable: URL,
        compilerDirectory: URL,
        label: String
    ) throws -> String {
        let llvmText = try runStageCompilerSourceSetDirective(
            executable: executable,
            compilerDirectory: compilerDirectory,
            directive: "compilerNativeSourceSetLLVMText",
            label: label
        )
        guard !llvmText.hasPrefix("compilerError\\t") else {
            throw SwiftBootstrapError(
                """
                \(label) failed in the Range-authored lowering pass.
                --- stdout ---
                \(prefixLines(llvmText, limit: 400))
                """
            )
        }
        return llvmText
    }

    private func stage2CandidateLLVMPath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage2", isDirectory: true)
            .appendingPathComponent("RangeCompiler.ll")
    }

    private func stage2CandidateExecutablePath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage2", isDirectory: true)
            .appendingPathComponent("RangeCompiler")
    }

    private func stage3CandidateLLVMPath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage3", isDirectory: true)
            .appendingPathComponent("RangeCompiler.ll")
    }

    private func stage3CandidateExecutablePath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage3", isDirectory: true)
            .appendingPathComponent("RangeCompiler")
    }

    private func compilerHostRuntimeSupportPath(rangeRoot: URL) -> URL {
        rangeRoot
            .deletingLastPathComponent()
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("RangeCompilerHost.c")
    }

    private func coreRuntimeSupportPaths(rangeRoot: URL) -> [URL] {
        let runtimeRoot = rangeRoot
            .deletingLastPathComponent()
            .appendingPathComponent("Runtime", isDirectory: true)
        return [
            runtimeRoot.appendingPathComponent("RangeCompilerMetrics.c"),
            runtimeRoot.appendingPathComponent("RangeTextBuffer.c"),
            runtimeRoot.appendingPathComponent("RangeIntBuffer.c"),
            runtimeRoot.appendingPathComponent("RangeString.c"),
        ]
    }

    private func stage2SmokeSourcePath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage2", isDirectory: true)
            .appendingPathComponent("Smoke.range")
    }

    private func stage2SmokeLLVMPath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage2", isDirectory: true)
            .appendingPathComponent("Smoke.ll")
    }

    private func stage2SmokeExecutablePath(compilerDirectory: URL) -> URL {
        compilerDirectory
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("stage2", isDirectory: true)
            .appendingPathComponent("Smoke")
    }

    private func checkLinkedStage2NormalCompile(
        executable: URL,
        runtimeInputs: [URL],
        compilerDirectory: URL
    ) throws {
        let smokeSource = stage2SmokeSourcePath(compilerDirectory: compilerDirectory)
        let smokeLLVM = stage2SmokeLLVMPath(compilerDirectory: compilerDirectory)
        let smokeExecutable = stage2SmokeExecutablePath(compilerDirectory: compilerDirectory)

        try """
        construct NativeSmokePair {
            let first: Int
            let second: Int
        }

        function nativeSmokeFirst(): NativeSmokePair {
            return NativeSmokePair(second: 2, first: 1)
        }

        function nativeSmokeSecond(): NativeSmokePair {
            return NativeSmokePair(first: 3, second: 6)
        }

        @main {
            let first: NativeSmokePair(nativeSmokeFirst())
            state second: NativeSmokePair(nativeSmokeSecond())
            second: NativeSmokePair(first: 3, second: 6)
            return first.first + second.second
        }
        """.write(to: smokeSource, atomically: true, encoding: .utf8)

        let compileResult = try runExecutable(executable: executable, arguments: [smokeSource.path], stdin: nil)
        guard compileResult.exitCode == 0 else {
            throw SwiftBootstrapError(
                """
                Linked Stage 2 compiler normal compile exited \(compileResult.exitCode): \(smokeSource.path)
                --- stdout ---
                \(prefixLines(compileResult.stdout))
                --- stderr ---
                \(prefixLines(compileResult.stderr))
                """
            )
        }

        guard compileResult.stderr.isEmpty,
            compileResult.stdout.contains("%Range.NativeSmokePair = type { i32, i32 }"),
            compileResult.stdout.contains("define i32 @main() {\nentry:"),
            compileResult.stdout.components(separatedBy: "define void @nativeSmoke").count == 3,
            compileResult.stdout.components(separatedBy: "call void @nativeSmoke").count == 3,
            compileResult.stdout.contains("define void @nativeSmokeFirst(ptr %returnDestination)"),
            compileResult.stdout.contains("define void @nativeSmokeSecond(ptr %returnDestination)"),
            compileResult.stdout.contains("%storage0 = alloca"),
            compileResult.stdout.contains("%storage1 = alloca"),
            compileResult.stdout.contains("insertvalue %Range.NativeSmokePair"),
            compileResult.stdout.contains("extractvalue"),
            !compileResult.stdout.contains("call %Range.NativeSmokePair"),
            !compileResult.stdout.contains("rangeConstruct"),
            !compileResult.stdout.contains("malloc"),
            !compileResult.stdout.contains("calloc"),
            !compileResult.stdout.contains("\\n")
        else {
            throw SwiftBootstrapError(
                """
                Linked Stage 2 compiler did not emit linkable normal-program LLVM.
                --- stdout ---
                \(prefixLines(compileResult.stdout))
                --- stderr ---
                \(prefixLines(compileResult.stderr))
                """
            )
        }

        let repeatCompileResult = try runExecutable(
            executable: executable,
            arguments: [smokeSource.path],
            stdin: nil
        )
        guard repeatCompileResult.exitCode == 0,
            repeatCompileResult.stderr.isEmpty,
            repeatCompileResult.stdout == compileResult.stdout
        else {
            throw SwiftBootstrapError(
                "Linked Stage 2 compiler normal compile was not deterministic."
            )
        }

        let mixedABISource = smokeSource.deletingLastPathComponent()
            .appendingPathComponent("MixedABINegative.range")
        try """
        construct ABIPair {
            let first: Int
            let second: Int
        }

        function brokenPair(): ABIPair {
            return 1
        }

        @main {
            let value: ABIPair(brokenPair())
            return value.first
        }
        """.write(to: mixedABISource, atomically: true, encoding: .utf8)
        let mixedABIResult = try runExecutable(
            executable: executable,
            arguments: [mixedABISource.path],
            stdin: nil
        )
        guard mixedABIResult.exitCode == 65,
            mixedABIResult.stderr.isEmpty,
            mixedABIResult.stdout.contains("compilerError\tkind=representationSensitiveABICapabilityBlocked"),
            !mixedABIResult.stdout.contains("define "),
            !mixedABIResult.stdout.contains("call ")
        else {
            throw SwiftBootstrapError(
                "Linked Stage 2 compiler did not reject a mixed aggregate ABI component before LLVM emission."
            )
        }

        try compileResult.stdout.write(to: smokeLLVM, atomically: true, encoding: .utf8)
        try validateLLVMIR(llvmIR: smokeLLVM)
        try linkExecutable(
            llvmIR: smokeLLVM,
            additionalInputs: runtimeInputs,
            executable: smokeExecutable
        )

        let runResult = try runExecutable(executable: smokeExecutable, arguments: [], stdin: nil)
        guard runResult.exitCode == 7, runResult.stdout.isEmpty, runResult.stderr.isEmpty else {
            throw SwiftBootstrapError(
                """
                Linked Stage 2 compiler normal executable failed.
                --- exit ---
                \(runResult.exitCode)
                --- stdout ---
                \(prefixLines(runResult.stdout))
                --- stderr ---
                \(prefixLines(runResult.stderr))
                """
            )
        }
    }

    private func checkLinkedStage2SelfRebuild(
        executable: URL,
        stage2LLVM: URL,
        runtimeInputs: [URL],
        compilerDirectory: URL
    ) throws -> URL {
        let stage3LLVMText = try runStageCompilerNativeLLVMText(
            executable: executable,
            compilerDirectory: compilerDirectory,
            label: "Linked Stage 2 self-rebuild"
        )
        guard !stage3LLVMText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SwiftBootstrapError(
                """
                Linked Stage 2 compiler did not emit Stage 3 LLVM text.
                --- materialized stdout ---
                \(prefixLines(stage3LLVMText))
                """
            )
        }

        let candidate = stage3CandidateLLVMPath(compilerDirectory: compilerDirectory)
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try stage3LLVMText.write(to: candidate, atomically: true, encoding: .utf8)
        try validateLLVMIR(llvmIR: candidate)
        try compareStageCompilerLLVM(stage2LLVM: stage2LLVM, stage3LLVM: candidate)

        let executable = stage3CandidateExecutablePath(compilerDirectory: compilerDirectory)
        try linkExecutable(
            llvmIR: candidate,
            additionalInputs: runtimeInputs,
            executable: executable
        )
        try checkLinkedStage2NormalCompile(
            executable: executable,
            runtimeInputs: runtimeInputs,
            compilerDirectory: compilerDirectory
        )
        return candidate
    }

    private func compareStageCompilerLLVM(stage2LLVM: URL, stage3LLVM: URL) throws {
        let stage2Data = try Data(contentsOf: stage2LLVM)
        let stage3Data = try Data(contentsOf: stage3LLVM)
        let stage2Text = try String(contentsOf: stage2LLVM, encoding: .utf8)
        let stage3Text = try String(contentsOf: stage3LLVM, encoding: .utf8)
        let requiredMarkers = [
            "define ptr @compileRangeNativeSource(ptr %source)",
            "define void @parseCompilerAssignmentStatement(ptr %returnDestination, %Range.RangeLexedToken %token",
            "define void @compilerCoreRenderedDirectIfElseStatementRecord(ptr %returnDestination, %Range.CompilerLLVMLoweringContext %context",
            "define i32 @main()",
            "call ptr @compileRangeNativeSource(ptr",
        ]
        for marker in requiredMarkers {
            guard stage2Text.contains(marker), stage3Text.contains(marker) else {
                throw SwiftBootstrapError("Stage compiler LLVM marker mismatch: \(marker)")
            }
        }
        guard !stage2Text.contains("stringEqual(ptr null"),
            !stage3Text.contains("stringEqual(ptr null"),
            !stage2Text.contains("add i1 %"),
            !stage3Text.contains("add i1 %")
        else {
            throw SwiftBootstrapError("Stage compiler LLVM contains a known-invalid lowering shape.")
        }

        guard stage2Data == stage3Data else {
            let stage2Lines = stage2Text.split(separator: "\n", omittingEmptySubsequences: false)
            let stage3Lines = stage3Text.split(separator: "\n", omittingEmptySubsequences: false)
            let sharedLineCount = min(stage2Lines.count, stage3Lines.count)
            var mismatchLine = sharedLineCount
            for index in 0..<sharedLineCount where stage2Lines[index] != stage3Lines[index] {
                mismatchLine = index
                break
            }
            let stage2Mismatch = mismatchLine < stage2Lines.count ? String(stage2Lines[mismatchLine]) : "<end of file>"
            let stage3Mismatch = mismatchLine < stage3Lines.count ? String(stage3Lines[mismatchLine]) : "<end of file>"
            throw SwiftBootstrapError(
                """
                Stage 2 and Stage 3 compiler LLVM are not byte-identical.
                First differing line: \(mismatchLine + 1)
                --- stage2 ---
                \(stage2Mismatch)
                --- stage3 ---
                \(stage3Mismatch)
                """
            )
        }
    }

    private func validateLLVMIR(llvmIR: URL) throws {
        let object = llvmIR.deletingPathExtension().appendingPathExtension("o")
        defer { try? FileManager.default.removeItem(at: object) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "clang",
            "-Wno-override-module",
            "-x",
            "ir",
            "-c",
            llvmIR.path,
            "-o",
            object.path,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stdoutText = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let details = [stderrText, stdoutText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if details.isEmpty {
                throw SwiftBootstrapError("clang could not parse LLVM IR: \(llvmIR.path)")
            }
            throw SwiftBootstrapError(details)
        }
    }

    private func sourceInput(for file: URL, role: SourceInputRole) throws -> SourceInput {
        SourceInput(
            path: file.path,
            source: try String(contentsOf: file, encoding: .utf8),
            role: role
        )
    }

    private func coreInputs(rangeRoot: URL) throws -> [SourceInput] {
        let roots = [
            rangeRoot.appendingPathComponent("Core", isDirectory: true),
            rangeRoot.appendingPathComponent("Foundation", isDirectory: true),
            rangeRoot.appendingPathComponent("Lexer", isDirectory: true),
        ]

        return try roots.flatMap { root in
            try rangeFiles(in: root).map { try sourceInput(for: $0, role: .core) }
        }
    }

    private func projectInputs(input: URL) throws -> [SourceInput] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw SwiftBootstrapError("Missing input: \(input.path)")
        }

        if isDirectory.boolValue {
            return try rangeFiles(in: input).map { try sourceInput(for: $0, role: .project) }
        }

        return [try sourceInput(for: input, role: .project)]
    }

    private func executableLayout(for input: URL) throws -> ExecutableLayout {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw SwiftBootstrapError("Missing input: \(input.path)")
        }

        let projectRoot: URL
        let executableName: String
        if isDirectory.boolValue {
            projectRoot = input
            executableName = input.lastPathComponent
        } else {
            projectRoot = input.deletingLastPathComponent()
            executableName = input.deletingPathExtension().lastPathComponent
        }

        let buildRoot = projectRoot
            .appendingPathComponent(".range", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("llvm", isDirectory: true)

        return ExecutableLayout(
            buildRoot: buildRoot,
            llvmIR: buildRoot.appendingPathComponent("Main.ll"),
            executable: buildRoot.appendingPathComponent(executableName)
        )
    }

    private func linkExecutable(
        llvmIR: URL,
        additionalInputs: [URL],
        executable: URL
    ) throws {
        let process = Process()
        let command = URL(fileURLWithPath: "/usr/bin/env")
        let arguments = [
            "clang",
            "-Wno-override-module",
            llvmIR.path,
        ] + additionalInputs.map(\.path) + [
                "-o",
                executable.path,
            ]
        let metricsURL = configureMeasuredProcess(process, executable: command, arguments: arguments)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()
        recordChildMetrics(at: metricsURL)

        guard process.terminationStatus == 0 else {
            let stderrText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stdoutText = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let details = [stderrText, stdoutText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if details.isEmpty {
                throw SwiftBootstrapError("clang failed with exit \(process.terminationStatus).")
            }
            throw SwiftBootstrapError(details)
        }
    }

    private func parseRunManifest(_ manifest: URL) throws -> [RunManifestEntry] {
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw SwiftBootstrapError("Missing LLVM run manifest: \(manifest.path)")
        }

        let manifestDirectory = manifest.deletingLastPathComponent()
        let text = try String(contentsOf: manifest, encoding: .utf8)
        var entries: [RunManifestEntry] = []

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
        {
            let lineNumber = index + 1
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
            guard columns.count >= 4 else {
                throw SwiftBootstrapError(
                    "Invalid manifest row \(lineNumber) in \(manifest.path): expected at least file, exit, stdin, and args columns."
                )
            }

            guard let expectedExit = Int32(columns[1]), expectedExit >= 0, expectedExit <= 255 else {
                throw SwiftBootstrapError(
                    "Invalid expected exit '\(columns[1])' on manifest row \(lineNumber) in \(manifest.path)."
                )
            }

            let source = sourceURL(for: columns[0], relativeTo: manifestDirectory)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw SwiftBootstrapError(
                    "Manifest row \(lineNumber) references missing source: \(source.path)"
                )
            }

            entries.append(
                RunManifestEntry(
                    source: source,
                    expectedExit: expectedExit,
                    stdin: columns[2] == "-" ? nil : decodeManifestEscapes(columns[2]),
                    arguments: columns[3] == "-" ? [] : shellLikeArguments(columns[3]),
                    expectedStdout: columns.count > 4 && columns[4] != "-"
                        ? decodeManifestEscapes(columns[4])
                        : nil
                )
            )
        }

        return entries
    }

    private func validateManifestCoverage(
        entries: [RunManifestEntry],
        manifest: URL,
        requireFullCoverage: Bool
    ) throws {
        let manifestNames = entries.map { $0.source.lastPathComponent }
        let duplicateNames = Dictionary(grouping: manifestNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        if !duplicateNames.isEmpty {
            throw SwiftBootstrapError(
                "Duplicate LLVM run manifest entries:\n\(duplicateNames.prefix(80).joined(separator: "\n"))"
            )
        }

        guard requireFullCoverage else {
            return
        }

        let manifestDirectory = manifest.deletingLastPathComponent()
        let corpusNames = try rangeFiles(in: manifestDirectory)
            .filter { $0.deletingLastPathComponent() == manifestDirectory }
            .map(\.lastPathComponent)
            .sorted()
        let manifestNameSet = Set(manifestNames)
        let corpusNameSet = Set(corpusNames)
        let missingNames = corpusNames.filter { !manifestNameSet.contains($0) }
        if !missingNames.isEmpty {
            throw SwiftBootstrapError(
                "LLVM run manifest is missing example(s):\n\(missingNames.prefix(120).joined(separator: "\n"))"
            )
        }

        let extraNames = manifestNames.sorted().filter { !corpusNameSet.contains($0) }
        if !extraNames.isEmpty {
            throw SwiftBootstrapError(
                "LLVM run manifest references non-corpus example(s):\n\(extraNames.prefix(120).joined(separator: "\n"))"
            )
        }
    }

    private func sourceURL(for path: String, relativeTo directory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return directory.appendingPathComponent(path)
    }

    private func runExecutable(
        executable: URL,
        arguments: [String],
        stdin: String?
    ) throws -> ExecutionResult {
        let process = Process()
        let metricsURL = configureMeasuredProcess(process, executable: executable, arguments: arguments)

        let captureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: captureDirectory) }

        let stdoutURL = captureDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = captureDirectory.appendingPathComponent("stderr.txt")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let stdinPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            stdinPipe = nil
        }

        try process.run()

        if let stdinPipe, let stdin {
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        recordChildMetrics(at: metricsURL)
        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        return ExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
    }

    private func measurePhase<T>(_ label: String, _ body: () throws -> T) throws -> T {
        phaseMetrics.begin()
        let sampler = ProcessRSSSampler(intervalMilliseconds: 100)
        sampler.start()
        let started = Date()
        defer {
            let selfPeak = sampler.stop()
            let childPeak = phaseMetrics.end()
            let elapsed = Date().timeIntervalSince(started)
            print(
                String(
                    format: "stageMetric\tphase=%@\telapsedSeconds=%.3f\tselfPeakRSSBytes=%llu\tchildPeakRSSBytes=%llu\trssSampleMilliseconds=100",
                    label,
                    elapsed,
                    selfPeak,
                    childPeak
                )
            )
        }
        return try body()
    }

    private func configureMeasuredProcess(
        _ process: Process,
        executable: URL,
        arguments: [String]
    ) -> URL? {
        guard phaseMetrics.isActive else {
            process.executableURL = executable
            process.arguments = arguments
            return nil
        }
        let metricsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("range-process-metrics-\(UUID().uuidString).txt")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["-l", "-o", metricsURL.path, executable.path] + arguments
        return metricsURL
    }

    private func recordChildMetrics(at metricsURL: URL?) {
        guard let metricsURL else { return }
        defer { try? FileManager.default.removeItem(at: metricsURL) }
        guard let text = try? String(contentsOf: metricsURL, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where line.contains("maximum resident set size") {
            if let value = UInt64(line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first ?? "") {
                phaseMetrics.recordChildPeak(value)
            }
        }
    }
}

private final class PhaseMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var childPeak: UInt64 = 0

    var isActive: Bool { lock.withLock { active } }

    func begin() {
        lock.withLock {
            active = true
            childPeak = 0
        }
    }

    func recordChildPeak(_ bytes: UInt64) {
        lock.withLock { childPeak = max(childPeak, bytes) }
    }

    func end() -> UInt64 {
        lock.withLock {
            active = false
            return childPeak
        }
    }
}

private final class ProcessRSSSampler: @unchecked Sendable {
    private let intervalMilliseconds: Int
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var timer: DispatchSourceTimer?

    init(intervalMilliseconds: Int) {
        self.intervalMilliseconds = intervalMilliseconds
    }

    func start() {
        sample()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + .milliseconds(intervalMilliseconds),
            repeating: .milliseconds(intervalMilliseconds)
        )
        timer.setEventHandler { self.sample() }
        self.timer = timer
        timer.resume()
    }

    func stop() -> UInt64 {
        timer?.cancel()
        timer = nil
        sample()
        return lock.withLock { peak }
    }

    private func sample() {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let read = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, pointer, size)
        }
        guard read == size else { return }
        lock.withLock { peak = max(peak, info.pti_resident_size) }
    }
}

private struct ExecutableLayout {
    var buildRoot: URL
    var llvmIR: URL
    var executable: URL
}

private struct RunManifestEntry {
    var source: URL
    var expectedExit: Int32
    var stdin: String?
    var arguments: [String]
    var expectedStdout: String?
}

private struct ExecutionResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private func shellLikeArguments(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
}

private func decodeManifestEscapes(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
        let character = text[index]
        guard character == "\\" else {
            result.append(character)
            index = text.index(after: index)
            continue
        }

        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex else {
            result.append(character)
            index = nextIndex
            continue
        }

        switch text[nextIndex] {
        case "n":
            result.append("\n")
        case "r":
            result.append("\r")
        case "t":
            result.append("\t")
        case "\\":
            result.append("\\")
        default:
            result.append(text[nextIndex])
        }
        index = text.index(after: nextIndex)
    }
    return result
}

private func prefixLines(_ text: String, limit: Int = 80) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        .prefix(limit)
        .map(String.init)
    return lines.joined(separator: "\n")
}
