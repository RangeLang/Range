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
            uniqueKeysWithValues: lowerableFunctions.compactMap {
                callable -> (String, LLVMFunctionEmitter.CallableSymbol)? in
                guard let signature = LLVMLowerability.scalarSignature(for: callable) else {
                    return nil
                }
                return (
                    callable.name,
                    LLVMFunctionEmitter.CallableSymbol(
                        symbolName: Self.symbolName(for: callable),
                        signature: signature
                    )
                )
            }
        )
        let stringTable = LLVMStringTable()
        for symbol in symbolsByName.values where symbol.signature.usesString {
            stringTable.requireStringType()
        }
        for symbol in symbolsByName.values where symbol.signature.usesIntArray {
            stringTable.requireIntArrayType()
        }
        let functions = try lowerableFunctions.map {
            try emitFunction($0, symbolsByName: symbolsByName, stringTable: stringTable)
        }
        .joined(separator: "\n\n")
        let support = stringTable.supportDefinitions()
        let supportBlock = support.isEmpty ? "" : "\n\(support)\n"
        let ir = """
            ; ModuleID = '\(moduleName)'
            source_filename = "\(moduleName).ll"
            \(supportBlock)
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
        symbolsByName: [String: LLVMFunctionEmitter.CallableSymbol],
        stringTable: LLVMStringTable
    ) throws -> String {
        guard let body = callable.body else {
            throw LLVMLoweringError("LLVM lowering requires function \(callable.name) to have a body.")
        }
        guard let signature = LLVMLowerability.scalarSignature(for: callable) else {
            throw LLVMLoweringError("LLVM lowering requires scalar function \(callable.name).")
        }

        var function = LLVMFunctionEmitter(
            signature: signature,
            parameters: callable.parameters,
            callableSymbolsByName: symbolsByName,
            stringTable: stringTable
        )
        try function.emitBody(body)
        let parameterList = zip(callable.parameters, signature.parameters)
            .map { parameter, type in "\(type.llvmType) %\(parameter.name)" }
            .joined(separator: ", ")
        let instructions = function.lines.joined(separator: "\n")

        let instructionBlock = instructions.isEmpty ? "" : "\(instructions)\n"
        return """
            define \(signature.returnType.llvmType) @\(Self.symbolName(for: callable))(\(parameterList)) {
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

private extension LLVMLowerability.ScalarType {
    var llvmType: String {
        switch self {
        case .int:
            return "i64"
        case .bool:
            return "i1"
        case .float:
            return "double"
        case .string:
            return "%Range.String"
        case .intArray:
            return "%Range.IntArray"
        }
    }
}

private extension LLVMLowerability.ScalarSignature {
    var usesString: Bool {
        returnType == .string || parameters.contains(.string)
    }

    var usesIntArray: Bool {
        returnType == .intArray || parameters.contains(.intArray)
    }
}

private final class LLVMStringTable {
    private var namesByValue: [String: String] = [:]
    private var requiresType = false
    private var requiresIntArrayType = false
    private var requiresMalloc = false

    func requireStringType() {
        requiresType = true
    }

    func requireIntArrayType() {
        requiresIntArrayType = true
    }

    func requireMalloc() {
        requiresMalloc = true
    }

    func constantName(for value: String) -> String {
        requireStringType()
        if let name = namesByValue[value] {
            return name
        }
        let name = "@.range.string.\(namesByValue.count)"
        namesByValue[value] = name
        return name
    }

    func supportDefinitions() -> String {
        guard requiresType || requiresIntArrayType || requiresMalloc else {
            return ""
        }
        var definitions: [String] = []
        if requiresType {
            definitions.append("%Range.String = type { ptr, i64 }")
        }
        if requiresIntArrayType {
            definitions.append("%Range.IntArray = type { ptr, i64, i64 }")
        }
        if requiresMalloc {
            definitions.append("declare ptr @malloc(i64)")
        }
        let globals = namesByValue.sorted { $0.value < $1.value }.map { value, name in
            let bytes = Array(value.utf8)
            return "\(name) = private unnamed_addr constant [\(bytes.count + 1) x i8] c\"\(llvmEscapedCString(bytes))\\00\", align 1"
        }
        return (definitions + globals).joined(separator: "\n")
    }

    private func llvmEscapedCString(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            switch byte {
            case 0x20...0x21, 0x23...0x5B, 0x5D...0x7E:
                return String(UnicodeScalar(byte))
            default:
                return String(format: "\\%02X", byte)
            }
        }.joined()
    }
}

private struct LLVMFunctionEmitter {
    private typealias ScalarType = LLVMLowerability.ScalarType

    private enum LowerableMember {
        case count
        case byteCount
        case element
        case isEmpty
        case update
    }

    struct CallableSymbol {
        let symbolName: String
        let signature: LLVMLowerability.ScalarSignature
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
    private let returnType: ScalarType
    private let callableSymbolsByName: [String: CallableSymbol]
    private let stringTable: LLVMStringTable
    private(set) var lines: [String] = []
    private var nextRegister = 0
    private var nextLabel = 0
    private var blockTerminated = false
    private var loopTargets: [(conditionLabel: String, endLabel: String)] = []

    init(
        signature: LLVMLowerability.ScalarSignature,
        parameters: [RangeFunctionParameter],
        callableSymbolsByName: [String: CallableSymbol],
        stringTable: LLVMStringTable
    ) {
        self.returnType = signature.returnType
        self.symbols = Dictionary(
            uniqueKeysWithValues: zip(parameters, signature.parameters).map {
                parameter, type in
                (parameter.name, Symbol.parameter(type))
            }
        )
        self.callableSymbolsByName = callableSymbolsByName
        self.stringTable = stringTable
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
        case .compoundAssignment(let target, let operatorSymbol, let expression):
            try emitCompoundAssignment(
                target: target,
                operatorSymbol: operatorSymbol,
                expression: expression
            )
        case .whileLoop(let condition, let body):
            try emitWhileLoop(condition: condition, body: body)
        case .conditional(let branches):
            try emitConditional(branches)
        case .switchStatement(let expression, let cases, let defaultBody):
            try emitSwitch(expression: expression, cases: cases, defaultBody: defaultBody)
        case .return(let expression?):
            let value = try emitExpression(expression)
            let converted = try convert(value, to: returnType)
            guard converted.type == returnType.llvmType else {
                throw LLVMLoweringError("LLVM return value must be \(returnType.llvmType).")
            }
            emit("ret \(returnType.llvmType) \(converted.representation)")
            blockTerminated = true
        case .return(nil):
            throw LLVMLoweringError("LLVM lowering does not support bare return.")
        case .break:
            guard let target = loopTargets.last else {
                throw LLVMLoweringError("LLVM break requires an enclosing loop.")
            }
            emitBranch(to: target.endLabel)
        case .continue:
            guard let target = loopTargets.last else {
                throw LLVMLoweringError("LLVM continue requires an enclosing loop.")
            }
            emitBranch(to: target.conditionLabel)
        case .macroInvocation, .expand, .background, .deferBlock, .localCallable, .derived,
            .forEach:
            throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
        case .expression(let expression):
            guard try emitLowerableSideEffectExpression(expression) else {
                throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
            }
        }
    }

    private mutating func emitLocalBinding(_ declaration: LocalBindingDeclaration) throws {
        guard let scalarType = ScalarType(typeReference: declaration.type) else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' must be Int, Bool, or Float.")
        }
        guard symbols[declaration.name] == nil else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' is already declared.")
        }

        let value = try emitExpression(declaration.expression)
        let converted = try convert(value, to: scalarType)
        guard converted.type == scalarType.llvmType else {
            throw LLVMLoweringError(
                "LLVM local binding initializer must be \(scalarType.llvmType)."
            )
        }

        let pointer = "%\(declaration.name).addr"
        emit("\(pointer) = alloca \(scalarType.llvmType)")
        emit("store \(scalarType.llvmType) \(converted.representation), ptr \(pointer)")
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
        let converted = try convert(value, to: type)
        guard converted.type == type.llvmType else {
            throw LLVMLoweringError("LLVM assignment value must be \(type.llvmType).")
        }
        emit("store \(type.llvmType) \(converted.representation), ptr \(pointer)")
    }

    private mutating func emitCompoundAssignment(
        target: AssignmentTarget,
        operatorSymbol: CompoundOperator,
        expression: RangeCompiler.Expression
    ) throws {
        guard case .plusEquals = operatorSymbol else {
            throw LLVMLoweringError("LLVM compound assignment currently supports += only.")
        }
        guard case .local(let name) = target else {
            throw LLVMLoweringError("LLVM compound assignment currently supports local state only.")
        }
        guard case .stackSlot(let pointer, let type, let mutable) = symbols[name],
            mutable
        else {
            throw LLVMLoweringError("LLVM compound assignment target '\(name)' is not mutable local state.")
        }

        let currentRegister = freshRegister()
        emit("\(currentRegister) = load \(type.llvmType), ptr \(pointer)")
        let currentValue = Value(type: type.llvmType, representation: currentRegister)
        let rhsValue = try emitExpression(expression)
        let sum = try emitBinaryExpression(
            lhsValue: currentValue,
            operatorSymbol: .addition,
            rhsValue: rhsValue
        )
        let converted = try convert(sum, to: type)
        guard converted.type == type.llvmType else {
            throw LLVMLoweringError("LLVM compound assignment value must be \(type.llvmType).")
        }
        emit("store \(type.llvmType) \(converted.representation), ptr \(pointer)")
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
        loopTargets.append((conditionLabel: conditionLabel, endLabel: endLabel))
        defer {
            _ = loopTargets.popLast()
        }
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

    private mutating func emitSwitch(
        expression: RangeCompiler.Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?
    ) throws {
        guard !cases.isEmpty else {
            throw LLVMLoweringError("LLVM switch requires at least one case.")
        }
        guard let defaultBody else {
            throw LLVMLoweringError("LLVM switch requires a default branch.")
        }

        let subject = try emitExpression(expression)
        guard subject.type == "i64" || subject.type == "i1" else {
            throw LLVMLoweringError("LLVM switch subject must be i64 or i1.")
        }

        let labelID = freshLabelID()
        let defaultLabel = "switch.default.\(labelID)"
        let endLabel = "switch.end.\(labelID)"
        let caseLabels = cases.indices.map { "switch.case.\(labelID).\($0)" }
        let caseLiterals = try cases.map { try switchCaseLiteral($0.pattern, subjectType: subject.type) }

        emit("switch \(subject.type) \(subject.representation), label %\(defaultLabel) [")
        for (literal, label) in zip(caseLiterals, caseLabels) {
            lines.append("    \(subject.type) \(literal), label %\(label)")
        }
        lines.append("  ]")
        blockTerminated = true

        var allBranchesTerminate = true
        for (switchCase, label) in zip(cases, caseLabels) {
            emitLabel(label)
            try emitStatements(switchCase.body)
            if !blockTerminated {
                allBranchesTerminate = false
                emitBranch(to: endLabel)
            }
        }

        emitLabel(defaultLabel)
        try emitStatements(defaultBody)
        if !blockTerminated {
            allBranchesTerminate = false
            emitBranch(to: endLabel)
        }

        if allBranchesTerminate {
            blockTerminated = true
        } else {
            emitLabel(endLabel)
        }
    }

    private mutating func emitStatements(_ statements: [Statement]) throws {
        for statement in statements {
            try emitStatement(statement)
            if blockTerminated {
                break
            }
        }
    }

    private mutating func emitExpression(_ expression: RangeCompiler.Expression) throws -> Value {
        switch expression {
        case .integer(let value):
            return Value(type: "i64", representation: String(value))
        case .double(let value):
            return Value(type: "double", representation: llvmDoubleLiteral(value))
        case .boolean(let value):
            return Value(type: "i1", representation: value ? "1" : "0")
        case .string(let value):
            let name = stringTable.constantName(for: value)
            let byteCount = value.utf8.count
            let pointerRegister = freshRegister()
            emit(
                "\(pointerRegister) = getelementptr inbounds [\(byteCount + 1) x i8], ptr \(name), i64 0, i64 0"
            )
            let storageRegister = freshRegister()
            emit("\(storageRegister) = insertvalue %Range.String undef, ptr \(pointerRegister), 0")
            let countRegister = freshRegister()
            emit("\(countRegister) = insertvalue %Range.String \(storageRegister), i64 \(byteCount), 1")
            return Value(type: "%Range.String", representation: countRegister)
        case .identifier(let name):
            if let member = try emitLowerableMemberAccess(name: name) {
                return member
            }
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
            return try emitBinaryExpression(
                lhsValue: lhsValue,
                operatorSymbol: operatorSymbol,
                rhsValue: rhsValue
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            let conditionValue = try emitExpression(condition)
            guard conditionValue.type == "i1" else {
                throw LLVMLoweringError("LLVM ternary condition must be i1.")
            }
            let trueValue = try emitExpression(trueExpression)
            let falseValue = try emitExpression(falseExpression)
            let resultType = try ternaryLLVMType(trueValue.type, falseValue.type)
            let convertedTrue = try convert(value: trueValue, toLLVMType: resultType)
            let convertedFalse = try convert(value: falseValue, toLLVMType: resultType)
            let register = freshRegister()
            emit(
                "\(register) = select i1 \(conditionValue.representation), \(resultType) \(convertedTrue.representation), \(resultType) \(convertedFalse.representation)"
            )
            return Value(type: resultType, representation: register)
        case .call(let name, let arguments):
            if let allocation = try emitLowerableIntArrayAllocation(
                name: name,
                arguments: arguments
            ) {
                return allocation
            }
            if let memberCall = try emitLowerableMemberCall(name: name, arguments: arguments) {
                return memberCall
            }
            guard let callable = callableSymbolsByName[name] else {
                throw LLVMLoweringError("LLVM lowering cannot resolve callable '\(name)'.")
            }
            let argumentValues = try arguments.map { try emitExpression($0.value) }
            guard argumentValues.count == callable.signature.parameters.count else {
                throw LLVMLoweringError("LLVM lowered call '\(name)' has wrong argument count.")
            }
            let convertedArguments = try zip(argumentValues, callable.signature.parameters).map {
                argumentValue, parameterType in
                let converted = try convert(argumentValue, to: parameterType)
                guard converted.type == parameterType.llvmType else {
                    throw LLVMLoweringError(
                        "LLVM lowered call '\(name)' argument must be \(parameterType.llvmType)."
                    )
                }
                return converted
            }
            let register = freshRegister()
            let argumentsText = zip(convertedArguments, callable.signature.parameters)
                .map { argumentValue, parameterType in
                    "\(parameterType.llvmType) \(argumentValue.representation)"
                }
                .joined(separator: ", ")
            emit(
                "\(register) = call \(callable.signature.returnType.llvmType) @\(callable.symbolName)(\(argumentsText))"
            )
            return Value(type: callable.signature.returnType.llvmType, representation: register)
        default:
            throw LLVMLoweringError("LLVM lowering does not support expression \(expression).")
        }
    }

    private mutating func emitLowerableMemberAccess(name: String) throws -> Value? {
        guard let dotIndex = name.lastIndex(of: ".") else {
            return nil
        }
        let baseName = String(name[..<dotIndex])
        let memberName = String(name[name.index(after: dotIndex)...])
        guard let member = lowerableMemberAccess(name: memberName) else {
            return nil
        }

        let base = try emitIdentifier(named: baseName)
        guard base.type == "%Range.String" || base.type == "%Range.IntArray" else {
            return nil
        }

        let countRegister = freshRegister()
        emit("\(countRegister) = extractvalue \(base.type) \(base.representation), 1")
        switch member {
        case .count:
            return Value(type: "i64", representation: countRegister)
        case .byteCount:
            return Value(type: "i64", representation: countRegister)
        case .element:
            return nil
        case .update:
            return nil
        case .isEmpty:
            let resultRegister = freshRegister()
            emit("\(resultRegister) = icmp eq i64 \(countRegister), 0")
            return Value(type: "i1", representation: resultRegister)
        }
    }

    private mutating func emitLowerableMemberCall(
        name: String,
        arguments: [CallArgument]
    ) throws -> Value? {
        guard let dotIndex = name.lastIndex(of: ".") else {
            return nil
        }
        let baseName = String(name[..<dotIndex])
        let memberName = String(name[name.index(after: dotIndex)...])
        guard lowerableMemberCall(name: memberName) == .element else {
            return nil
        }
        guard arguments.count == 1 else {
            throw LLVMLoweringError("LLVM Array<Int>.element expects one index argument.")
        }

        let base = try emitIdentifier(named: baseName)
        guard base.type == "%Range.IntArray" else {
            return nil
        }
        let rawIndex = try emitExpression(arguments[0].value)
        let index = try convert(value: rawIndex, toLLVMType: "i64")
        guard index.type == "i64" else {
            throw LLVMLoweringError("LLVM Array<Int>.element index must be i64.")
        }

        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = extractvalue %Range.IntArray \(base.representation), 0")
        let elementPointerRegister = freshRegister()
        emit(
            "\(elementPointerRegister) = getelementptr inbounds i64, ptr \(pointerRegister), i64 \(index.representation)"
        )
        let valueRegister = freshRegister()
        emit("\(valueRegister) = load i64, ptr \(elementPointerRegister)")
        return Value(type: "i64", representation: valueRegister)
    }

    private mutating func emitLowerableIntArrayAllocation(
        name: String,
        arguments: [CallArgument]
    ) throws -> Value? {
        guard name == "intArray" else {
            return nil
        }
        guard arguments.count == 1 else {
            throw LLVMLoweringError("LLVM intArray allocation expects one capacity argument.")
        }
        guard arguments[0].label == "capacity" || arguments[0].label == nil else {
            throw LLVMLoweringError("LLVM intArray allocation expects a capacity argument.")
        }

        let rawCapacity = try emitExpression(arguments[0].value)
        let capacity = try convert(value: rawCapacity, toLLVMType: "i64")
        guard capacity.type == "i64" else {
            throw LLVMLoweringError("LLVM intArray allocation capacity must be i64.")
        }

        stringTable.requireIntArrayType()
        stringTable.requireMalloc()
        let byteCountRegister = freshRegister()
        emit("\(byteCountRegister) = mul i64 \(capacity.representation), 8")
        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = call ptr @malloc(i64 \(byteCountRegister))")
        let pointerValueRegister = freshRegister()
        emit(
            "\(pointerValueRegister) = insertvalue %Range.IntArray undef, ptr \(pointerRegister), 0"
        )
        let countValueRegister = freshRegister()
        emit(
            "\(countValueRegister) = insertvalue %Range.IntArray \(pointerValueRegister), i64 \(capacity.representation), 1"
        )
        let capacityValueRegister = freshRegister()
        emit(
            "\(capacityValueRegister) = insertvalue %Range.IntArray \(countValueRegister), i64 \(capacity.representation), 2"
        )
        return Value(type: "%Range.IntArray", representation: capacityValueRegister)
    }

    private mutating func emitLowerableSideEffectExpression(
        _ expression: RangeCompiler.Expression
    ) throws -> Bool {
        guard case .call(let name, let arguments) = expression,
            let dotIndex = name.lastIndex(of: ".")
        else {
            return false
        }
        let baseName = String(name[..<dotIndex])
        let memberName = String(name[name.index(after: dotIndex)...])
        guard memberName == "update" else {
            return false
        }
        guard arguments.count == 2 else {
            throw LLVMLoweringError("LLVM Array<Int>.update expects element and index arguments.")
        }

        let base = try emitIdentifier(named: baseName)
        guard base.type == "%Range.IntArray" else {
            return false
        }
        guard let elementExpression = argumentValue(labeled: "element", at: 0, in: arguments),
            let indexExpression = argumentValue(labeled: "index", at: 1, in: arguments)
        else {
            throw LLVMLoweringError("LLVM Array<Int>.update expects element and index arguments.")
        }

        let rawElement = try emitExpression(elementExpression)
        let element = try convert(value: rawElement, toLLVMType: "i64")
        guard element.type == "i64" else {
            throw LLVMLoweringError("LLVM Array<Int>.update element must be i64.")
        }
        let rawIndex = try emitExpression(indexExpression)
        let index = try convert(value: rawIndex, toLLVMType: "i64")
        guard index.type == "i64" else {
            throw LLVMLoweringError("LLVM Array<Int>.update index must be i64.")
        }

        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = extractvalue %Range.IntArray \(base.representation), 0")
        let elementPointerRegister = freshRegister()
        emit(
            "\(elementPointerRegister) = getelementptr inbounds i64, ptr \(pointerRegister), i64 \(index.representation)"
        )
        emit("store i64 \(element.representation), ptr \(elementPointerRegister)")
        return true
    }

    private func lowerableMemberAccess(name: String) -> LowerableMember? {
        switch name {
        case "count":
            return .count
        case "byteCount":
            return .byteCount
        case "isEmpty":
            return .isEmpty
        default:
            return nil
        }
    }

    private func lowerableMemberCall(name: String) -> LowerableMember? {
        switch name {
        case "element":
            return .element
        case "update":
            return .update
        default:
            return nil
        }
    }

    private func argumentValue(
        labeled label: String,
        at fallbackIndex: Int,
        in arguments: [CallArgument]
    ) -> RangeCompiler.Expression? {
        if let labeledArgument = arguments.first(where: { $0.label == label }) {
            return labeledArgument.value
        }
        guard arguments.indices.contains(fallbackIndex) else {
            return nil
        }
        return arguments[fallbackIndex].value
    }

    private mutating func emitIdentifier(named name: String) throws -> Value {
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

    private func llvmDoubleLiteral(_ value: Double) -> String {
        let raw = String(value)
        guard let exponentIndex = raw.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return raw
        }
        let mantissa = raw[..<exponentIndex]
        guard !mantissa.contains(".") else {
            return raw
        }
        return "\(mantissa).0\(raw[exponentIndex...])"
    }

    private mutating func emitBinaryExpression(
        lhsValue: Value,
        operatorSymbol: BinaryOperator,
        rhsValue: Value
    ) throws -> Value {
        let instruction = try llvmInstruction(
            for: operatorSymbol,
            lhsType: lhsValue.type,
            rhsType: rhsValue.type
        )
        let convertedLHS = try convert(value: lhsValue, toLLVMType: instruction.operandType)
        let convertedRHS = try convert(value: rhsValue, toLLVMType: instruction.operandType)
        let register = freshRegister()
        emit(
            "\(register) = \(instruction.mnemonic) \(instruction.operandType) \(convertedLHS.representation), \(convertedRHS.representation)"
        )
        return Value(type: instruction.resultType, representation: register)
    }

    private func ternaryLLVMType(_ lhsType: String, _ rhsType: String) throws -> String {
        if lhsType == rhsType {
            return lhsType
        }
        if (lhsType == "i64" && rhsType == "double")
            || (lhsType == "double" && rhsType == "i64")
        {
            return "double"
        }
        throw LLVMLoweringError("LLVM ternary branches must have compatible scalar types.")
    }

    private mutating func convert(_ value: Value, to scalarType: ScalarType) throws -> Value {
        try convert(value: value, toLLVMType: scalarType.llvmType)
    }

    private mutating func convert(value: Value, toLLVMType llvmType: String) throws -> Value {
        if value.type == llvmType {
            return value
        }
        if value.type == "i64", llvmType == "double" {
            let register = freshRegister()
            emit("\(register) = sitofp i64 \(value.representation) to double")
            return Value(type: "double", representation: register)
        }
        return value
    }

    private func switchCaseLiteral(_ pattern: SwitchCasePattern, subjectType: String) throws -> String {
        guard case .expression(let expression) = pattern else {
            throw LLVMLoweringError("LLVM switch only supports literal expression cases.")
        }

        switch (subjectType, expression) {
        case ("i64", .integer(let value)):
            return String(value)
        case ("i1", .boolean(let value)):
            return value ? "1" : "0"
        default:
            throw LLVMLoweringError("LLVM switch case literal must match the switch subject.")
        }
    }

    private func llvmInstruction(
        for operatorSymbol: BinaryOperator,
        lhsType: String,
        rhsType: String
    ) throws -> (
        mnemonic: String, operandType: String, resultType: String
    ) {
        switch operatorSymbol {
        case .addition, .subtraction, .multiplication, .division:
            if lhsType == "double" || rhsType == "double" {
                return (floatArithmeticMnemonic(for: operatorSymbol), "double", "double")
            }
            guard lhsType == "i64", rhsType == "i64" else {
                throw LLVMLoweringError(
                    "LLVM \(operatorSymbol.rawValue) operands must be numeric.")
            }
            return (intArithmeticMnemonic(for: operatorSymbol), "i64", "i64")
        case .remainder:
            guard lhsType == "i64", rhsType == "i64" else {
                throw LLVMLoweringError("LLVM % operands must be i64.")
            }
            return ("srem", "i64", "i64")
        case .equal, .notEqual:
            if lhsType == "double" || rhsType == "double" {
                return (floatComparisonMnemonic(for: operatorSymbol), "double", "i1")
            }
            if lhsType == "i64", rhsType == "i64" {
                return (intComparisonMnemonic(for: operatorSymbol), "i64", "i1")
            }
            if lhsType == "i1", rhsType == "i1" {
                return (intComparisonMnemonic(for: operatorSymbol), "i1", "i1")
            }
            throw LLVMLoweringError("LLVM \(operatorSymbol.rawValue) operands must match.")
        case .less, .lessEqual, .greater, .greaterEqual:
            if lhsType == "double" || rhsType == "double" {
                return (floatComparisonMnemonic(for: operatorSymbol), "double", "i1")
            }
            guard lhsType == "i64", rhsType == "i64" else {
                throw LLVMLoweringError(
                    "LLVM \(operatorSymbol.rawValue) operands must be numeric.")
            }
            return (intComparisonMnemonic(for: operatorSymbol), "i64", "i1")
        case .and:
            guard lhsType == "i1", rhsType == "i1" else {
                throw LLVMLoweringError("LLVM && operands must be i1.")
            }
            return ("and", "i1", "i1")
        case .or:
            guard lhsType == "i1", rhsType == "i1" else {
                throw LLVMLoweringError("LLVM || operands must be i1.")
            }
            return ("or", "i1", "i1")
        case .nilCoalescing:
            throw LLVMLoweringError(
                "LLVM lowering does not support operator '\(operatorSymbol.rawValue)' yet.")
        case .rangeUntil, .closedRange:
            throw LLVMLoweringError(
                "LLVM lowering does not support operator '\(operatorSymbol.rawValue)' yet.")
        }
    }

    private func intArithmeticMnemonic(for operatorSymbol: BinaryOperator) -> String {
        switch operatorSymbol {
        case .addition:
            return "add"
        case .subtraction:
            return "sub"
        case .multiplication:
            return "mul"
        case .division:
            return "sdiv"
        default:
            return ""
        }
    }

    private func floatArithmeticMnemonic(for operatorSymbol: BinaryOperator) -> String {
        switch operatorSymbol {
        case .addition:
            return "fadd"
        case .subtraction:
            return "fsub"
        case .multiplication:
            return "fmul"
        case .division:
            return "fdiv"
        default:
            return ""
        }
    }

    private func intComparisonMnemonic(for operatorSymbol: BinaryOperator) -> String {
        switch operatorSymbol {
        case .equal:
            return "icmp eq"
        case .notEqual:
            return "icmp ne"
        case .less:
            return "icmp slt"
        case .lessEqual:
            return "icmp sle"
        case .greater:
            return "icmp sgt"
        case .greaterEqual:
            return "icmp sge"
        default:
            return ""
        }
    }

    private func floatComparisonMnemonic(for operatorSymbol: BinaryOperator) -> String {
        switch operatorSymbol {
        case .equal:
            return "fcmp oeq"
        case .notEqual:
            return "fcmp one"
        case .less:
            return "fcmp olt"
        case .lessEqual:
            return "fcmp ole"
        case .greater:
            return "fcmp ogt"
        case .greaterEqual:
            return "fcmp oge"
        default:
            return ""
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
