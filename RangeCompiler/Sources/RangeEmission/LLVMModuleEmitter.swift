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
        var locals: [String: Int] = [:]

        for statement in mainBlock.body {
            switch statement {
            case .localBinding(let declaration):
                locals[declaration.name] = try integerValue(from: declaration.expression, locals: locals)

            case .assignment(let target, let expression):
                let name = try integerLocalName(from: target)
                guard locals[name] != nil else {
                    throw LLVMEmissionError("Unknown LLVM integer local '\(name)'.")
                }
                locals[name] = try integerValue(from: expression, locals: locals)

            case .return(let expression):
                guard let expression else {
                    return 0
                }
                return try integerValue(from: expression, locals: locals)

            default:
                throw LLVMEmissionError(
                    "LLVM emission currently supports only integer locals, assignment, and integer returns."
                )
            }
        }

        return 0
    }

    private func integerValue(
        from expression: RangeCompiler.Expression,
        locals: [String: Int]
    ) throws -> Int {
        switch expression {
        case .integer(let value):
            return value
        case .identifier(let name):
            guard let value = locals[name] else {
                throw LLVMEmissionError("Unknown LLVM integer local '\(name)'.")
            }
            return value
        case .call(let name, let arguments)
            where name == "Int" && arguments.count == 1 && arguments[0].label == nil:
            return try integerValue(from: arguments[0].value, locals: locals)
        case .binary(let lhs, let operatorSymbol, let rhs):
            let left = try integerValue(from: lhs, locals: locals)
            let right = try integerValue(from: rhs, locals: locals)
            return try evaluateIntegerBinary(
                lhs: left,
                operatorSymbol: operatorSymbol,
                rhs: right
            )
        default:
            throw LLVMEmissionError("LLVM emission currently supports integer values only.")
        }
    }

    private func evaluateIntegerBinary(
        lhs: Int,
        operatorSymbol: BinaryOperator,
        rhs: Int
    ) throws -> Int {
        switch operatorSymbol {
        case .addition:
            return lhs + rhs
        case .subtraction:
            return lhs - rhs
        case .multiplication:
            return lhs * rhs
        case .division:
            guard rhs != 0 else {
                throw LLVMEmissionError("LLVM integer division by zero.")
            }
            return lhs / rhs
        case .remainder:
            guard rhs != 0 else {
                throw LLVMEmissionError("LLVM integer remainder by zero.")
            }
            return lhs % rhs
        default:
            throw LLVMEmissionError("LLVM emission currently supports integer arithmetic only.")
        }
    }

    private func integerLocalName(from target: AssignmentTarget) throws -> String {
        switch target {
        case .local(let name), .state(let name):
            return name
        case .binding(let name):
            throw LLVMEmissionError("LLVM emission cannot assign to binding '\(name)' yet.")
        case .member:
            throw LLVMEmissionError("LLVM emission cannot assign to member targets yet.")
        }
    }
}
