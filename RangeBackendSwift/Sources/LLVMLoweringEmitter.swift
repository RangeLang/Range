import Foundation
import RangeSyntax

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
    func emitModule(program: LoweredProgram, moduleName: String = "RangeScalar") throws
        -> LLVMModuleEmission?
    {
        let callables = program.callables + program.units.flatMap(\.callables)
        let lowerableFunctions = uniqueLowerableFunctions(from: callables)
        guard !lowerableFunctions.isEmpty else {
            return nil
        }

        let functions = try lowerableFunctions.map(emitFunction).joined(separator: "\n\n")
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

    private func emitFunction(_ callable: CallableDeclaration) throws -> String {
        guard let body = callable.body else {
            throw LLVMLoweringError("LLVM lowering requires function \(callable.name) to have a body.")
        }

        var function = LLVMFunctionEmitter(parameters: callable.parameters)
        let returnValue = try function.emitBody(body)
        let parameterList = callable.parameters.map { "i64 %\($0.name)" }.joined(separator: ", ")
        let instructions = function.lines.joined(separator: "\n")

        let instructionBlock = instructions.isEmpty ? "" : "\(instructions)\n"
        return """
            define i64 @\(Self.symbolName(for: callable))(\(parameterList)) {
            entry:
            \(instructionBlock)  ret i64 \(returnValue)
            }
            """
    }

    static func symbolName(for callable: CallableDeclaration) -> String {
        "RangeLLVM_" + sanitizeSymbol(callable.name)
    }

    private func uniqueLowerableFunctions(from callables: [CallableDeclaration])
        -> [CallableDeclaration]
    {
        var seenSymbols: Set<String> = []
        var functions: [CallableDeclaration] = []

        for callable in callables where LLVMLowerability.canLower(callable) {
            let symbol = Self.symbolName(for: callable)
            guard seenSymbols.insert(symbol).inserted else {
                continue
            }
            functions.append(callable)
        }

        return functions
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
    private enum Symbol {
        case parameter
        case stackSlot(String)
    }

    private struct Value {
        let type: String
        let representation: String
    }

    private var symbols: [String: Symbol]
    private(set) var lines: [String] = []
    private var nextRegister = 0
    private var nextLabel = 0
    private var blockTerminated = false

    init(parameters: [RangeFunctionParameter]) {
        self.symbols = Dictionary(
            uniqueKeysWithValues: parameters.map { ($0.name, Symbol.parameter) }
        )
    }

    mutating func emitBody(_ body: [Statement]) throws -> String {
        for statement in body {
            if let returnValue = try emitStatement(statement) {
                return returnValue
            }
        }

        throw LLVMLoweringError("LLVM lowering requires an explicit return statement.")
    }

    private mutating func emitStatement(_ statement: Statement) throws -> String? {
        switch statement {
        case .localBinding(let declaration):
            try emitLocalBinding(declaration)
            return nil
        case .assignment(let target, let expression):
            try emitAssignment(target: target, expression: expression)
            return nil
        case .whileLoop(let condition, let body):
            try emitWhileLoop(condition: condition, body: body)
            return nil
        case .return(let expression?):
            let value = try emitExpression(expression)
            guard value.type == "i64" else {
                throw LLVMLoweringError("LLVM return value must be i64.")
            }
            blockTerminated = true
            return value.representation
        case .return(nil):
            throw LLVMLoweringError("LLVM lowering does not support bare return.")
        case .macroInvocation, .expand, .background, .deferBlock, .localCallable, .derived,
            .compoundAssignment, .expression, .forEach, .conditional, .break, .continue,
            .switchStatement:
            throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
        }
    }

    private mutating func emitLocalBinding(_ declaration: LocalBindingDeclaration) throws {
        guard declaration.type.displayName == "Int" else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' must be Int.")
        }
        guard symbols[declaration.name] == nil else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' is already declared.")
        }

        let value = try emitExpression(declaration.expression)
        guard value.type == "i64" else {
            throw LLVMLoweringError("LLVM local binding initializer must be i64.")
        }

        let pointer = "%\(declaration.name).addr"
        emit("\(pointer) = alloca i64")
        emit("store i64 \(value.representation), ptr \(pointer)")
        symbols[declaration.name] = .stackSlot(pointer)
    }

    private mutating func emitAssignment(
        target: AssignmentTarget,
        expression: RangeSyntax.Expression
    ) throws {
        guard case .local(let name) = target else {
            throw LLVMLoweringError("LLVM assignment currently supports local state only.")
        }
        guard case .stackSlot(let pointer) = symbols[name] else {
            throw LLVMLoweringError("LLVM assignment target '\(name)' is not a local state slot.")
        }

        let value = try emitExpression(expression)
        guard value.type == "i64" else {
            throw LLVMLoweringError("LLVM assignment value must be i64.")
        }
        emit("store i64 \(value.representation), ptr \(pointer)")
    }

    private mutating func emitWhileLoop(
        condition: RangeSyntax.Expression,
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
            if let returnValue = try emitStatement(statement) {
                emit("ret i64 \(returnValue)")
                blockTerminated = true
                break
            }
        }
        if !blockTerminated {
            emitBranch(to: conditionLabel)
        }

        emitLabel(endLabel)
    }

    private mutating func emitExpression(_ expression: RangeSyntax.Expression) throws -> Value {
        switch expression {
        case .integer(let value):
            return Value(type: "i64", representation: String(value))
        case .identifier(let name):
            guard let symbol = symbols[name] else {
                throw LLVMLoweringError("LLVM lowering cannot resolve identifier '\(name)'.")
            }
            switch symbol {
            case .parameter:
                return Value(type: "i64", representation: "%\(name)")
            case .stackSlot(let pointer):
                let register = freshRegister()
                emit("\(register) = load i64, ptr \(pointer)")
                return Value(type: "i64", representation: register)
            }
        case .binary(let lhs, let operatorSymbol, let rhs):
            let lhsValue = try emitExpression(lhs)
            let rhsValue = try emitExpression(rhs)
            guard lhsValue.type == "i64", rhsValue.type == "i64" else {
                throw LLVMLoweringError("LLVM binary operands must be i64.")
            }
            let instruction = try llvmInstruction(for: operatorSymbol)
            let register = freshRegister()
            emit(
                "\(register) = \(instruction.mnemonic) i64 \(lhsValue.representation), \(rhsValue.representation)"
            )
            return Value(type: instruction.resultType, representation: register)
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
        mnemonic: String, resultType: String
    ) {
        switch operatorSymbol {
        case .addition:
            return ("add", "i64")
        case .subtraction:
            return ("sub", "i64")
        case .multiplication:
            return ("mul", "i64")
        case .division:
            return ("sdiv", "i64")
        case .remainder:
            return ("srem", "i64")
        case .equal:
            return ("icmp eq", "i1")
        case .notEqual:
            return ("icmp ne", "i1")
        case .less:
            return ("icmp slt", "i1")
        case .lessEqual:
            return ("icmp sle", "i1")
        case .greater:
            return ("icmp sgt", "i1")
        case .greaterEqual:
            return ("icmp sge", "i1")
        case .and, .or, .nilCoalescing:
            throw LLVMLoweringError(
                "LLVM lowering does not support operator '\(operatorSymbol.rawValue)' yet.")
        }
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
