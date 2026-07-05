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
        private struct LLVMValue {
            let type: String
            let operand: String
        }

        private var instructions: [String] = []
        private var locals: [String: String] = [:]
        private var temporaryIndex = 0
        private var labelIndex = 0
        private var returned = false
        private var blockTerminated = false
        private var loopStack: [(breakLabel: String, continueLabel: String)] = []

        mutating func emit(mainBlock: MainBlockNode) throws -> String {
            for statement in mainBlock.body {
                try emit(statement: statement)
                if returned || blockTerminated {
                    break
                }
            }

            if !returned {
                instructions.append("ret i32 0")
            }

            let body = instructions.map { line in
                line.hasSuffix(":") ? line : "  \(line)"
            }.joined(separator: "\n")
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
                let value = try emitValue(from: declaration.expression)
                guard value.type == "i32" else {
                    throw LLVMEmissionError("LLVM locals currently support i32 values only.")
                }
                let pointer = try declareLocal(named: declaration.name)
                instructions.append("store i32 \(value.operand), ptr \(pointer)")

            case .assignment(let target, let expression):
                let name = try integerLocalName(from: target)
                guard let pointer = locals[name] else {
                    throw LLVMEmissionError("Unknown LLVM integer local '\(name)'.")
                }
                let value = try emitValue(from: expression)
                guard value.type == "i32" else {
                    throw LLVMEmissionError("LLVM assignments currently support i32 values only.")
                }
                instructions.append("store i32 \(value.operand), ptr \(pointer)")

            case .return(let expression):
                guard let expression else {
                    instructions.append("ret i32 0")
                    returned = true
                    blockTerminated = true
                    return
                }
                let value = try emitValue(from: expression)
                let returnOperand = try emitI32ReturnOperand(from: value)
                instructions.append("ret i32 \(returnOperand)")
                returned = true
                blockTerminated = true

            case .conditional(let branches):
                try emitConditional(branches)

            case .whileLoop(let condition, let body):
                try emitWhileLoop(condition: condition, body: body)

            case .break:
                guard let loop = loopStack.last else {
                    throw LLVMEmissionError("LLVM break requires an enclosing loop.")
                }
                instructions.append("br label %\(loop.breakLabel)")
                blockTerminated = true

            case .continue:
                guard let loop = loopStack.last else {
                    throw LLVMEmissionError("LLVM continue requires an enclosing loop.")
                }
                instructions.append("br label %\(loop.continueLabel)")
                blockTerminated = true

            default:
                throw LLVMEmissionError(
                    "LLVM emission currently supports integer locals, assignment, control flow, and returns."
                )
            }
        }

        private mutating func emitConditional(_ branches: [StatementConditionalBranch]) throws {
            guard !branches.isEmpty else {
                return
            }

            let endLabel = nextLabel("if.end")
            let branchLabels = branches.map { _ in nextLabel("if.then") }
            let checkLabels = branches.indices.map { index -> String? in
                index == 0 || branches[index].condition == nil ? nil : nextLabel("if.check")
            }
            let hasElseBranch = branches.contains { $0.condition == nil }

            for index in branches.indices {
                let branch = branches[index]
                let branchLabel = branchLabels[index]
                let nextTarget = conditionalFallthroughLabel(
                    after: index,
                    branches: branches,
                    branchLabels: branchLabels,
                    checkLabels: checkLabels,
                    endLabel: endLabel
                )

                if let checkLabel = checkLabels[index] {
                    instructions.append("\(checkLabel):")
                }

                if let condition = branch.condition {
                    let conditionValue = try emitCondition(from: condition)
                    instructions.append(
                        "br i1 \(conditionValue), label %\(branchLabel), label %\(nextTarget)"
                    )
                } else if index == 0 {
                    instructions.append("br label %\(branchLabel)")
                }

                instructions.append("\(branchLabel):")
                let branchReturned = try emitNestedStatements(branch.body)
                if !branchReturned {
                    instructions.append("br label %\(endLabel)")
                }
            }

            if !hasElseBranch {
                instructions.append("\(endLabel):")
                returned = false
                return
            }

            let allBranchesReturned = branches.allSatisfy { branch in
                branch.body.contains { statement in
                    if case .return = statement {
                        return true
                    }
                    return false
                }
            }

            if allBranchesReturned {
                returned = true
                blockTerminated = true
            } else {
                instructions.append("\(endLabel):")
                returned = false
                blockTerminated = false
            }
        }

        private func conditionalFallthroughLabel(
            after index: Int,
            branches: [StatementConditionalBranch],
            branchLabels: [String],
            checkLabels: [String?],
            endLabel: String
        ) -> String {
            let nextIndex = index + 1
            guard nextIndex < branches.count else {
                return endLabel
            }
            if branches[nextIndex].condition == nil {
                return branchLabels[nextIndex]
            }
            return checkLabels[nextIndex] ?? branchLabels[nextIndex]
        }

        private mutating func emitNestedStatements(_ statements: [Statement]) throws -> Bool {
            let outerReturned = returned
            let outerBlockTerminated = blockTerminated
            returned = false
            blockTerminated = false
            for statement in statements {
                try emit(statement: statement)
                if returned || blockTerminated {
                    break
                }
            }
            let nestedTerminated = returned || blockTerminated
            returned = outerReturned
            blockTerminated = outerBlockTerminated
            return nestedTerminated
        }

        private mutating func emitWhileLoop(
            condition: RangeCompiler.Expression,
            body: [Statement]
        ) throws {
            let conditionLabel = nextLabel("while.condition")
            let bodyLabel = nextLabel("while.body")
            let endLabel = nextLabel("while.end")

            instructions.append("br label %\(conditionLabel)")
            instructions.append("\(conditionLabel):")
            let conditionValue = try emitCondition(from: condition)
            instructions.append("br i1 \(conditionValue), label %\(bodyLabel), label %\(endLabel)")

            instructions.append("\(bodyLabel):")
            loopStack.append((breakLabel: endLabel, continueLabel: conditionLabel))
            let bodyTerminated = try emitNestedStatements(body)
            _ = loopStack.popLast()
            if !bodyTerminated {
                instructions.append("br label %\(conditionLabel)")
            }

            instructions.append("\(endLabel):")
            returned = false
            blockTerminated = false
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

        private mutating func emitValue(from expression: RangeCompiler.Expression) throws -> LLVMValue {
            switch expression {
            case .integer(let value):
                return LLVMValue(type: "i32", operand: "\(value)")

            case .boolean(let value):
                return LLVMValue(type: "i1", operand: value ? "1" : "0")

            case .identifier(let name):
                guard let pointer = locals[name] else {
                    throw LLVMEmissionError("Unknown LLVM integer local '\(name)'.")
                }
                let result = nextTemporary()
                instructions.append("\(result) = load i32, ptr \(pointer)")
                return LLVMValue(type: "i32", operand: result)

            case .call(let name, let arguments)
                where name == "Int" && arguments.count == 1 && arguments[0].label == nil:
                let value = try emitValue(from: arguments[0].value)
                guard value.type == "i32" else {
                    throw LLVMEmissionError("Int(...) expects an integer LLVM value.")
                }
                return value

            case .call(let name, let arguments)
                where name == "Bool" && arguments.count == 1 && arguments[0].label == nil:
                let value = try emitValue(from: arguments[0].value)
                guard value.type == "i1" else {
                    throw LLVMEmissionError("Bool(...) expects a boolean LLVM value.")
                }
                return value

            case .binary(let lhs, let operatorSymbol, let rhs):
                return try emitBinaryValue(lhs: lhs, operatorSymbol: operatorSymbol, rhs: rhs)

            default:
                throw LLVMEmissionError("LLVM emission currently supports integer and boolean values only.")
            }
        }

        private mutating func emitBinaryValue(
            lhs: RangeCompiler.Expression,
            operatorSymbol: BinaryOperator,
            rhs: RangeCompiler.Expression
        ) throws -> LLVMValue {
            switch operatorSymbol {
            case .addition, .subtraction, .multiplication, .division, .remainder:
                let left = try emitValue(from: lhs)
                let right = try emitValue(from: rhs)
                guard left.type == "i32", right.type == "i32" else {
                    throw LLVMEmissionError("LLVM integer arithmetic requires i32 operands.")
                }
                let result = nextTemporary()
                instructions.append(
                    "\(result) = \(try llvmIntegerInstruction(for: operatorSymbol)) i32 \(left.operand), \(right.operand)"
                )
                return LLVMValue(type: "i32", operand: result)

            case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
                let left = try emitValue(from: lhs)
                let right = try emitValue(from: rhs)
                guard left.type == right.type else {
                    throw LLVMEmissionError("LLVM comparison operands must have matching types.")
                }
                guard left.type == "i32" || left.type == "i1" else {
                    throw LLVMEmissionError("LLVM comparison currently supports i32 and i1 operands.")
                }
                let result = nextTemporary()
                instructions.append(
                    "\(result) = icmp \(try llvmComparisonPredicate(for: operatorSymbol, operandType: left.type)) \(left.type) \(left.operand), \(right.operand)"
                )
                return LLVMValue(type: "i1", operand: result)

            default:
                throw LLVMEmissionError("LLVM emission does not support this binary operator yet.")
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

        private func llvmComparisonPredicate(
            for operatorSymbol: BinaryOperator,
            operandType: String
        ) throws -> String {
            switch operatorSymbol {
            case .equal:
                return "eq"
            case .notEqual:
                return "ne"
            case .less where operandType == "i32":
                return "slt"
            case .lessEqual where operandType == "i32":
                return "sle"
            case .greater where operandType == "i32":
                return "sgt"
            case .greaterEqual where operandType == "i32":
                return "sge"
            default:
                throw LLVMEmissionError("LLVM ordered comparison requires i32 operands.")
            }
        }

        private mutating func emitI32ReturnOperand(from value: LLVMValue) throws -> String {
            switch value.type {
            case "i32":
                return value.operand
            case "i1":
                let result = nextTemporary()
                instructions.append("\(result) = zext i1 \(value.operand) to i32")
                return result
            default:
                throw LLVMEmissionError("LLVM @main currently returns only i32-compatible values.")
            }
        }

        private mutating func emitCondition(from expression: RangeCompiler.Expression) throws -> String {
            let value = try emitValue(from: expression)
            switch value.type {
            case "i1":
                return value.operand
            case "i32":
                let result = nextTemporary()
                instructions.append("\(result) = icmp ne i32 \(value.operand), 0")
                return result
            default:
                throw LLVMEmissionError("LLVM branch conditions must be i1 or i32.")
            }
        }

        private mutating func nextTemporary() -> String {
            defer { temporaryIndex += 1 }
            return "%\(temporaryIndex)"
        }

        private mutating func nextLabel(_ prefix: String) -> String {
            defer { labelIndex += 1 }
            return "\(prefix).\(labelIndex)"
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
