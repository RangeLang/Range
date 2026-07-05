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
        var emitter = MainFunctionEmitter()
        return try emitter.emit(mainBlock: mainBlock)
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

    private struct MainFunctionEmitter {
        private var instructions: [String] = []
        private var locals: [String: String] = [:]
        private var temporaryIndex = 0
        private var returned = false

        mutating func emit(mainBlock: MainBlockNode) throws -> String {
            for statement in mainBlock.body {
                try emit(statement: statement)
            }

            if !returned {
                instructions.append("ret i32 0")
            }

            let body = instructions.map { "  \($0)" }.joined(separator: "\n")
            return """
            define i32 @main() {
            entry:
            \(body)
            }

            """
        }

        private mutating func emit(statement: Statement) throws {
            switch statement {
            case .localBinding(let declaration):
                let value = try emitIntegerValue(from: declaration.expression)
                let pointer = try declareLocal(named: declaration.name)
                instructions.append("store i32 \(value), ptr \(pointer)")

            case .assignment(let target, let expression):
                let name = try integerLocalName(from: target)
                guard let pointer = locals[name] else {
                    throw LLVMEmissionError("Unknown LLVM integer local '\(name)'.")
                }
                let value = try emitIntegerValue(from: expression)
                instructions.append("store i32 \(value), ptr \(pointer)")

            case .return(let expression):
                guard let expression else {
                    instructions.append("ret i32 0")
                    returned = true
                    return
                }
                let value = try emitIntegerValue(from: expression)
                instructions.append("ret i32 \(value)")
                returned = true

            default:
                throw LLVMEmissionError(
                    "LLVM emission currently supports only integer locals, assignment, and integer returns."
                )
            }
        }

        private mutating func declareLocal(named name: String) throws -> String {
            if locals[name] != nil {
                throw LLVMEmissionError("Duplicate LLVM integer local '\(name)'.")
            }
            let pointer = "%\(try llvmIdentifier(name))"
            locals[name] = pointer
            instructions.append("\(pointer) = alloca i32")
            return pointer
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

        private mutating func emitIntegerValue(from expression: RangeCompiler.Expression) throws
            -> String
        {
            switch expression {
            case .integer(let value):
                return "\(value)"

            case .identifier(let name):
                guard let pointer = locals[name] else {
                    throw LLVMEmissionError("Unknown LLVM integer local '\(name)'.")
                }
                let result = nextTemporary()
                instructions.append("\(result) = load i32, ptr \(pointer)")
                return result

            case .call(let name, let arguments)
                where name == "Int" && arguments.count == 1 && arguments[0].label == nil:
                return try emitIntegerValue(from: arguments[0].value)

            case .binary(let lhs, let operatorSymbol, let rhs):
                let left = try emitIntegerValue(from: lhs)
                let right = try emitIntegerValue(from: rhs)
                let result = nextTemporary()
                instructions.append(
                    "\(result) = \(try llvmIntegerInstruction(for: operatorSymbol)) i32 \(left), \(right)"
                )
                return result

            default:
                throw LLVMEmissionError("LLVM emission currently supports integer values only.")
            }
        }

        private func llvmIntegerInstruction(for operatorSymbol: BinaryOperator) throws -> String {
            switch operatorSymbol {
            case .addition:
                return "add"
            case .subtraction:
                return "sub"
            case .multiplication:
                return "mul"
            case .division:
                return "sdiv"
            case .remainder:
                return "srem"
            default:
                throw LLVMEmissionError("LLVM emission currently supports integer arithmetic only.")
            }
        }

        private mutating func nextTemporary() -> String {
            defer { temporaryIndex += 1 }
            return "%\(temporaryIndex)"
        }

        private func llvmIdentifier(_ name: String) throws -> String {
            guard !name.isEmpty else {
                throw LLVMEmissionError("LLVM local names cannot be empty.")
            }
            let scalars = name.unicodeScalars
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$.-"))
            guard scalars.allSatisfy({ allowed.contains($0) }) else {
                throw LLVMEmissionError("Unsupported LLVM local name '\(name)'.")
            }
            guard let first = scalars.first,
                !CharacterSet.decimalDigits.contains(first)
            else {
                throw LLVMEmissionError("LLVM local names cannot start with a digit.")
            }
            return name
        }
    }
}
