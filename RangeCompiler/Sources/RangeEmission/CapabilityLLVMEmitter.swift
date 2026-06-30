import Foundation
import RangeCompiler

public struct CapabilityLLVMModule: Equatable {
    public let ir: String
}

public struct CapabilityLLVMEmitterError: LocalizedError, Equatable {
    public let message: String

    public var errorDescription: String? {
        message
    }

    static let missingMacroProducedIR = CapabilityLLVMEmitterError(
        message: "Range source did not emit macro-produced LLVM IR."
    )
}

public struct CapabilityLLVMEmitter {
    public init() {}

    public func emitModule(compiledProgram: CompiledProgram) throws -> CapabilityLLVMModule {
        try emitModule(files: compiledProgram.expandedFiles)
    }

    public func emitModule(files: [ParsedSourceFile]) throws -> CapabilityLLVMModule {
        guard let ir = collectMainIR(files: files)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !ir.isEmpty
        else {
            throw CapabilityLLVMEmitterError.missingMacroProducedIR
        }

        return CapabilityLLVMModule(ir: ir)
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

    public func collectMainIR(files: [ParsedSourceFile]) -> String? {
        files.compactMap { file -> String? in
            file.sourceFile.blockMacros
                .compactMap { block -> String? in
                    guard block.macros.first?.name == "main" else {
                        return nil
                    }
                    return block.macros.first(where: { $0.name == "main" })?
                        .evaluatedStringValue
                }
                .first
        }.first
    }
}
