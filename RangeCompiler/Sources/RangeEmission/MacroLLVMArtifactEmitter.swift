import Foundation
import RangeCompiler

public struct MacroLLVMArtifactModule: Equatable {
    public let ir: String
}

public struct MacroLLVMArtifactEmitterError: LocalizedError, Equatable {
    public let message: String

    public var errorDescription: String? {
        message
    }

    static let missingMacroProducedIR = MacroLLVMArtifactEmitterError(
        message: "Range source did not emit macro-produced LLVM IR."
    )
}

public struct MacroLLVMArtifactEmitter {
    public init() {}

    public func emitModule(compiledProgram: CompiledProgram) throws -> MacroLLVMArtifactModule {
        try emitModule(files: compiledProgram.expandedFiles)
    }

    public func emitModule(files: [ParsedSourceFile]) throws -> MacroLLVMArtifactModule {
        guard let ir = collectLLVMModuleIR(files: files)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !ir.isEmpty
        else {
            throw MacroLLVMArtifactEmitterError.missingMacroProducedIR
        }

        return MacroLLVMArtifactModule(ir: ir)
    }

    public func emitModuleFile(
        compiledProgram: CompiledProgram,
        outputURL: URL
    ) throws -> URL {
        let module = try emitModule(compiledProgram: compiledProgram)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (module.ir + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    public func collectLLVMModuleIR(files: [ParsedSourceFile]) -> String? {
        files.compactMap { file -> String? in
            file.sourceFile.blockMacros
                .compactMap { block -> String? in
                    block.macros.compactMap { application in
                        llvmModuleArtifactBody(application.evaluatedStringValue)
                    }.first
                }
                .first
        }.first
    }

    private func llvmModuleArtifactBody(_ value: String?) -> String? {
        let prefix = "artifact|kind=llvm-module|body="
        guard let value, value.hasPrefix(prefix) else {
            return nil
        }
        return String(value.dropFirst(prefix.count))
    }
}
