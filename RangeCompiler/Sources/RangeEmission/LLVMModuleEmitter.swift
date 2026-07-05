import Foundation
import RangeCompiler

public struct LLVMEmissionError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct LLVMModuleEmitter {
    public init() {}

    public func emit(program: CompiledProgram) throws -> String {
        let mainBlock = try projectMainBlock(in: program)
        let returnCode = try mainReturnCode(from: mainBlock)

        return """
        define i32 @main() {
        entry:
          ret i32 \(returnCode)
        }

        """
    }

    private func projectMainBlock(in program: CompiledProgram) throws -> MainBlockNode {
        let blocks = program.projectExpandedFiles.compactMap { file in
            mainBlock(in: file.sourceFile)
        }

        guard let block = blocks.first else {
            throw LLVMEmissionError("No @main block found in project source.")
        }

        guard blocks.count == 1 else {
            throw LLVMEmissionError("LLVM emission requires exactly one @main block.")
        }

        return block
    }

    private func mainBlock(in sourceFile: SourceFileNode) -> MainBlockNode? {
        switch sourceFile {
        case .mainBlock(let mainBlock):
            return mainBlock
        case .module(let module):
            return module.mainBlock
        default:
            return nil
        }
    }

    private func mainReturnCode(from mainBlock: MainBlockNode) throws -> Int {
        guard !mainBlock.body.isEmpty else {
            return 0
        }

        guard mainBlock.body.count == 1 else {
            throw LLVMEmissionError(
                "LLVM emission currently supports only empty @main blocks or a single integer return."
            )
        }

        guard case .return(let expression) = mainBlock.body[0] else {
            throw LLVMEmissionError(
                "LLVM emission currently supports only empty @main blocks or a single integer return."
            )
        }

        guard let expression else {
            return 0
        }

        return try integerReturnCode(from: expression)
    }

    private func integerReturnCode(from expression: RangeCompiler.Expression) throws -> Int {
        switch expression {
        case .integer(let value):
            return value
        case .call(let name, let arguments)
            where name == "Int" && arguments.count == 1 && arguments[0].label == nil:
            guard case .integer(let value) = arguments[0].value else {
                throw LLVMEmissionError("Int(...) return values must wrap an integer literal.")
            }
            return value
        default:
            throw LLVMEmissionError("LLVM emission currently supports integer return values only.")
        }
    }
}
