import Foundation
import RangeCompiler

struct LLVMModuleEmission: Equatable {
    let moduleName: String
    let ir: String
    let loweredSymbols: [LLVMLoweredSymbol]
}

struct LLVMLoweredSymbol: Equatable {
    let rangeName: String
    let llvmName: String
}

struct LLVMLoweringEmitter {
    func emitModule(callables lowerableFunctions: [CallableDeclaration], moduleName: String = "RangeScalar") throws
        -> LLVMModuleEmission?
    {
        guard !lowerableFunctions.isEmpty else {
            return nil
        }

        let symbolsByName = Dictionary(
            uniqueKeysWithValues: lowerableFunctions.map {
                ($0.name, Self.symbolName(for: $0))
            }
        )
        let functions = try lowerableFunctions.map {
            try emitFunction($0, symbolsByName: symbolsByName)
        }
        .joined(separator: "\n\n")
        let ir = """
            ; ModuleID = '\(moduleName)'
            source_filename = "\(moduleName).ll"

            \(functions)
            """

        return LLVMModuleEmission(
            moduleName: moduleName,
            ir: ir + "\n",
            loweredSymbols: lowerableFunctions.map {
                LLVMLoweredSymbol(rangeName: $0.name, llvmName: Self.symbolName(for: $0))
            }
        )
    }

    private func emitFunction(
        _ callable: CallableDeclaration,
        symbolsByName: [String: String]
    ) throws -> String {
        guard let body = callable.body else {
            throw LLVMLoweringError("LLVM lowering requires function \(callable.name) to have a body.")
        }

        var function = LLVMFunctionEmitter(
            parameters: callable.parameters,
            callableSymbolsByName: symbolsByName
        )
        try function.emitBody(body)
        let parameterList = callable.parameters.map { "i64 %\($0.name)" }.joined(separator: ", ")
        let instructions = function.lines.joined(separator: "\n")

        let instructionBlock = instructions.isEmpty ? "" : "\(instructions)\n"
        return """
            define i64 @\(Self.symbolName(for: callable))(\(parameterList)) {
            entry:
            \(instructionBlock)}
            """
    }

    static func symbolName(for callable: CallableDeclaration) -> String {
        "RangeLLVM_" + sanitizeSymbol(callable.name)
    }

    private static func sanitizeSymbol(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        return String(scalars)
    }
}

private struct LLVMFunctionEmitter {
    private enum ScalarType {
        case int
        case bool

        var llvmType: String {
            switch self {
            case .int:
                return "i64"
            case .bool:
                return "i1"
            }
        }

        init?(typeReference: TypeReference) {
            switch typeReference.displayName {
            case "Int":
                self = .int
            case "Bool":
                self = .bool
            default:
                return nil
            }
        }
    }

    private enum Symbol {
        case parameter(ScalarType)
        case stackSlot(pointer: String, type: ScalarType, mutable: Bool)
    }

    private struct Value {
        let type: String
        let representation: String
    }

    private var symbols: [String: Symbol]
    private let callableSymbolsByName: [String: String]
    private(set) var lines: [String] = []
    private var nextRegister = 0
    private var nextLabel = 0
    private var blockTerminated = false

    init(parameters: [RangeFunctionParameter], callableSymbolsByName: [String: String]) {
        self.symbols = Dictionary(
            uniqueKeysWithValues: parameters.map { ($0.name, Symbol.parameter(.int)) }
        )
        self.callableSymbolsByName = callableSymbolsByName
    }

    mutating func emitBody(_ body: [Statement]) throws {
        for statement in body {
            try emitStatement(statement)
            if blockTerminated {
                break
            }
        }

        guard blockTerminated else {
            throw LLVMLoweringError("LLVM lowering requires an explicit return statement.")
        }
    }

    private mutating func emitStatement(_ statement: Statement) throws {
        switch statement {
        case .localBinding(let declaration):
            try emitLocalBinding(declaration)
        case .assignment(let target, let expression):
            try emitAssignment(target: target, expression: expression)
        case .whileLoop(let condition, let body):
            try emitWhileLoop(condition: condition, body: body)
        case .conditional(let branches):
            try emitConditional(branches)
        case .return(let expression?):
            let value = try emitExpression(expression)
            guard value.type == "i64" else {
                throw LLVMLoweringError("LLVM return value must be i64.")
            }
            emit("ret i64 \(value.representation)")
            blockTerminated = true
        case .return(nil):
            throw LLVMLoweringError("LLVM lowering does not support bare return.")
        case .macroInvocation, .expand, .background, .deferBlock, .localCallable, .derived,
            .compoundAssignment, .expression, .forEach, .break, .continue,
            .switchStatement:
            throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
        }
    }

    private mutating func emitLocalBinding(_ declaration: LocalBindingDeclaration) throws {
        guard let scalarType = ScalarType(typeReference: declaration.type) else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' must be Int or Bool.")
        }
        guard symbols[declaration.name] == nil else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' is already declared.")
        }

        let value = try emitExpression(declaration.expression)
        guard value.type == scalarType.llvmType else {
            throw LLVMLoweringError(
                "LLVM local binding initializer must be \(scalarType.llvmType)."
            )
        }

        let pointer = "%\(declaration.name).addr"
        emit("\(pointer) = alloca \(scalarType.llvmType)")
        emit("store \(scalarType.llvmType) \(value.representation), ptr \(pointer)")
        symbols[declaration.name] = .stackSlot(
            pointer: pointer,
            type: scalarType,
            mutable: isMutable(declaration.kind)
        )
    }

    private mutating func emitAssignment(
        target: AssignmentTarget,
        expression: RangeCompiler.Expression
    ) throws {
        guard case .local(let name) = target else {
            throw LLVMLoweringError("LLVM assignment currently supports local state only.")
        }
        guard case .stackSlot(let pointer, let type, let mutable) = symbols[name],
            mutable
        else {
            throw LLVMLoweringError("LLVM assignment target '\(name)' is not mutable local state.")
        }

        let value = try emitExpression(expression)
        guard value.type == type.llvmType else {
            throw LLVMLoweringError("LLVM assignment value must be \(type.llvmType).")
        }
        emit("store \(type.llvmType) \(value.representation), ptr \(pointer)")
    }

    private mutating func emitWhileLoop(
        condition: RangeCompiler.Expression,
        body: [Statement]
    ) throws {
        let labelID = freshLabelID()
        let conditionLabel = "while.cond.\(labelID)"
        let bodyLabel = "while.body.\(labelID)"
        let endLabel = "while.end.\(labelID)"

        emitBranch(to: conditionLabel)
        emitLabel(conditionLabel)
        let conditionValue = try emitExpression(condition)
        guard conditionValue.type == "i1" else {
            throw LLVMLoweringError("LLVM while condition must be i1.")
        }
        emit("br i1 \(conditionValue.representation), label %\(bodyLabel), label %\(endLabel)")
        blockTerminated = true

        emitLabel(bodyLabel)
        for statement in body {
            try emitStatement(statement)
            if blockTerminated {
                break
            }
        }
        if !blockTerminated {
            emitBranch(to: conditionLabel)
        }

        emitLabel(endLabel)
    }

    private mutating func emitConditional(_ branches: [StatementConditionalBranch]) throws {
        guard !branches.isEmpty else {
            throw LLVMLoweringError("LLVM conditional requires at least one branch.")
        }

        let labelID = freshLabelID()
        let endLabel = "if.end.\(labelID)"
        let hasElse = branches.contains { $0.condition == nil }
        var allBranchesTerminate = hasElse

        for (index, branch) in branches.enumerated() {
            let bodyLabel = "if.body.\(labelID).\(index)"
            let nextLabel = "if.next.\(labelID).\(index)"

            if let condition = branch.condition {
                let conditionValue = try emitExpression(condition)
                guard conditionValue.type == "i1" else {
                    throw LLVMLoweringError("LLVM if condition must be i1.")
                }
                let falseLabel = index == branches.count - 1 ? endLabel : nextLabel
                emit(
                    "br i1 \(conditionValue.representation), label %\(bodyLabel), label %\(falseLabel)"
                )
                blockTerminated = true
            } else {
                emitBranch(to: bodyLabel)
            }

            emitLabel(bodyLabel)
            for statement in branch.body {
                try emitStatement(statement)
                if blockTerminated {
                    break
                }
            }

            if blockTerminated {
                if branch.condition == nil || index == branches.count - 1 {
                    allBranchesTerminate = allBranchesTerminate && true
                }
            } else {
                allBranchesTerminate = false
                emitBranch(to: endLabel)
            }

            if branch.condition != nil, index < branches.count - 1 {
                emitLabel(nextLabel)
            }
        }

        if allBranchesTerminate {
            blockTerminated = true
        } else {
            emitLabel(endLabel)
        }
    }

    private mutating func emitExpression(_ expression: RangeCompiler.Expression) throws -> Value {
        switch expression {
        case .integer(let value):
            return Value(type: "i64", representation: String(value))
        case .boolean(let value):
            return Value(type: "i1", representation: value ? "1" : "0")
        case .identifier(let name):
            guard let symbol = symbols[name] else {
                throw LLVMLoweringError("LLVM lowering cannot resolve identifier '\(name)'.")
            }
            switch symbol {
            case .parameter(let type):
                return Value(type: type.llvmType, representation: "%\(name)")
            case .stackSlot(let pointer, let type, _):
                let register = freshRegister()
                emit("\(register) = load \(type.llvmType), ptr \(pointer)")
                return Value(type: type.llvmType, representation: register)
            }
        case .unary(.not, let expression):
            let value = try emitExpression(expression)
            guard value.type == "i1" else {
                throw LLVMLoweringError("LLVM ! operand must be i1.")
            }
            let register = freshRegister()
            emit("\(register) = xor i1 \(value.representation), true")
            return Value(type: "i1", representation: register)
        case .binary(let lhs, let operatorSymbol, let rhs):
            let lhsValue = try emitExpression(lhs)
            let rhsValue = try emitExpression(rhs)
            let instruction = try llvmInstruction(for: operatorSymbol)
            guard lhsValue.type == instruction.operandType,
                rhsValue.type == instruction.operandType
            else {
                throw LLVMLoweringError(
                    "LLVM \(operatorSymbol.rawValue) operands must be \(instruction.operandType)."
                )
            }
            let register = freshRegister()
            emit(
                "\(register) = \(instruction.mnemonic) \(instruction.operandType) \(lhsValue.representation), \(rhsValue.representation)"
            )
            return Value(type: instruction.resultType, representation: register)
        case .call(let name, let arguments):
            guard let symbol = callableSymbolsByName[name] else {
                throw LLVMLoweringError("LLVM lowering cannot resolve callable '\(name)'.")
            }
            let argumentValues = try arguments.map { try emitExpression($0.value) }
            guard argumentValues.allSatisfy({ $0.type == "i64" }) else {
                throw LLVMLoweringError("LLVM lowered calls currently require i64 arguments.")
            }
            let register = freshRegister()
            let argumentsText = argumentValues
                .map { "i64 \($0.representation)" }
                .joined(separator: ", ")
            emit("\(register) = call i64 @\(symbol)(\(argumentsText))")
            return Value(type: "i64", representation: register)
        default:
            throw LLVMLoweringError("LLVM lowering does not support expression \(expression).")
        }
    }

    private mutating func emit(_ line: String) {
        lines.append("  \(line)")
        blockTerminated = false
    }

    private mutating func emitBranch(to label: String) {
        emit("br label %\(label)")
        blockTerminated = true
    }

    private mutating func emitLabel(_ label: String) {
        lines.append("\(label):")
        blockTerminated = false
    }

    private mutating func freshRegister() -> String {
        nextRegister += 1
        return "%\(nextRegister)"
    }

    private mutating func freshLabelID() -> Int {
        nextLabel += 1
        return nextLabel
    }

    private func llvmInstruction(for operatorSymbol: BinaryOperator) throws -> (
        mnemonic: String, operandType: String, resultType: String
    ) {
        switch operatorSymbol {
        case .addition:
            return ("add", "i64", "i64")
        case .subtraction:
            return ("sub", "i64", "i64")
        case .multiplication:
            return ("mul", "i64", "i64")
        case .division:
            return ("sdiv", "i64", "i64")
        case .remainder:
            return ("srem", "i64", "i64")
        case .equal:
            return ("icmp eq", "i64", "i1")
        case .notEqual:
            return ("icmp ne", "i64", "i1")
        case .less:
            return ("icmp slt", "i64", "i1")
        case .lessEqual:
            return ("icmp sle", "i64", "i1")
        case .greater:
            return ("icmp sgt", "i64", "i1")
        case .greaterEqual:
            return ("icmp sge", "i64", "i1")
        case .and:
            return ("and", "i1", "i1")
        case .or:
            return ("or", "i1", "i1")
        case .nilCoalescing:
            throw LLVMLoweringError(
                "LLVM lowering does not support operator '\(operatorSymbol.rawValue)' yet.")
        }
    }

    private func isMutable(_ kind: LocalBindingKind) -> Bool {
        guard case .mutable = kind else {
            return false
        }
        return true
    }
}

enum LLVMLoweringError: Error, CustomStringConvertible {
    case message(String)

    init(_ message: String) {
        self = .message(message)
    }

    var description: String {
        switch self {
        case .message(let message):
            return message
        }
    }
}
