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
    func emitModule(
        callables: [CallableDeclaration],
        constructLayouts: [String: LLVMLowerability.ConstructLayout] = [:],
        scalarTypes: [String: LLVMLowerability.ScalarType] = [:],
        moduleName: String = "RangeScalar"
    ) throws
        -> LLVMModuleEmission?
    {
        guard !callables.isEmpty else {
            return nil
        }

        let symbolsByName = Dictionary(
            uniqueKeysWithValues: callables.compactMap {
                callable -> (String, LLVMFunctionEmitter.CallableSymbol)? in
                guard let signature = LLVMLowerability.scalarSignature(
                    for: callable,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ) else {
                    return nil
                }
                return (
                    Self.callableKey(for: callable),
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
        for symbol in symbolsByName.values {
            symbol.signature.requireArrayTypes(in: stringTable)
        }
        for layout in constructLayouts.values {
            stringTable.requireConstructType(layout)
            for field in layout.fields {
                switch field.type {
                case .string:
                    stringTable.requireStringType()
                case .array:
                    stringTable.requireArrayType(field.type)
                case .int(_, _), .bool, .float, .construct:
                    break
                }
            }
        }
        let functions = try callables.map {
            try emitFunction(
                $0,
                symbolsByName: symbolsByName,
                stringTable: stringTable,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            )
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
            loweredSymbols: callables.map {
                LLVMLoweredSymbol(
                    rangeName: Self.callableKey(for: $0),
                    llvmName: Self.symbolName(for: $0)
                )
            }
        )
    }

    private func emitFunction(
        _ callable: CallableDeclaration,
        symbolsByName: [String: LLVMFunctionEmitter.CallableSymbol],
        stringTable: LLVMStringTable,
        constructLayouts: [String: LLVMLowerability.ConstructLayout],
        scalarTypes: [String: LLVMLowerability.ScalarType]
    ) throws -> String {
        guard let body = callable.body else {
            throw LLVMLoweringError("LLVM lowering requires function \(callable.name) to have a body.")
        }
        guard let signature = LLVMLowerability.scalarSignature(
            for: callable,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        ) else {
            throw LLVMLoweringError("LLVM lowering requires scalar function \(callable.name).")
        }

        var function = LLVMFunctionEmitter(
            signature: signature,
            parameters: callable.parameters,
            callableSymbolsByName: symbolsByName,
            stringTable: stringTable,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        )
        try function.emitBody(body.map(LLVMStatement.init(source:)))
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
        if callableKey(for: callable) == "main", callable.parameters.isEmpty {
            return "main"
        }
        return "RangeLLVM_" + sanitizeSymbol(callableKey(for: callable))
    }

    static func callableKey(for callable: CallableDeclaration) -> String {
        guard let owner = callable.targetType ?? callable.receiverType else {
            return callable.name
        }
        return "\(owner.displayName).\(callable.name)"
    }

    static func constructTypeName(identity: String, name: String) -> String {
        let suffix = identity == "construct:\(name)" ? "" : "_\(stableShortSuffix(identity))"
        return "%Range.\(sanitizeSymbol(name))\(suffix)"
    }

    static func sanitizeSymbol(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        return String(scalars)
    }

    private static func stableShortSuffix(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%08llx", hash & 0xffff_ffff)
    }
}

private extension LLVMLowerability.ScalarType {
    var llvmType: String {
        switch self {
        case .int(let bits, _):
            return "i\(bits)"
        case .bool:
            return "i1"
        case .float:
            return "double"
        case .string:
            return "%Range.String"
        case .array:
            return arrayLLVMTypeName
        case .construct(let identity, let name):
            return LLVMLoweringEmitter.constructTypeName(identity: identity, name: name)
        }
    }

    var arrayLLVMTypeName: String {
        guard case .array(let element) = self else {
            return llvmType
        }
        switch element {
        case .int:
            return "%Range.IntArray"
        case .bool:
            return "%Range.BoolArray"
        case .float:
            return "%Range.FloatArray"
        case .string:
            return "%Range.StringArray"
        case .array:
            return "%Range.ArrayArray"
        case .construct(_, let name):
            return "%Range.\(LLVMLoweringEmitter.sanitizeSymbol(name))Array"
        }
    }

    var arrayElementType: LLVMLowerability.ScalarType? {
        guard case .array(let element) = self else {
            return nil
        }
        return element
    }

    var arrayElementByteStride: Int {
        guard let element = arrayElementType else {
            return 0
        }
        switch element {
        case .bool:
            return 1
        case .int(let bits, _):
            return max(1, bits / 8)
        case .float:
            return 8
        case .string, .array, .construct:
            return 8
        }
    }

    func requireArrayTypes(in table: LLVMStringTable) {
        if case .array = self {
            table.requireArrayType(self)
        }
    }

    var isInteger: Bool {
        if case .int(_, _) = self {
            return true
        }
        return false
    }

    var isSignedInteger: Bool? {
        guard case .int(_, let signed) = self else {
            return nil
        }
        return signed
    }
}

private func isLLVMIntegerType(_ type: String) -> Bool {
    guard type.first == "i", type.count > 1 else {
        return false
    }
    return Int(type.dropFirst()) != nil
}

private extension LLVMLowerability.ScalarSignature {
    var usesString: Bool {
        returnType == .string || parameters.contains(.string)
    }

    func requireArrayTypes(in table: LLVMStringTable) {
        for type in [returnType] + parameters {
            type.requireArrayTypes(in: table)
        }
    }
}

private final class LLVMStringTable {
    private var namesByValue: [String: String] = [:]
    private var requiresType = false
    private var requiredArrayTypes: [String: LLVMLowerability.ScalarType] = [:]
    private var requiresMalloc = false
    private var requiresFree = false
    private var requiresMemcpy = false
    private var requiresTrap = false
    private var requiredConstructTypes: [String: LLVMLowerability.ConstructLayout] = [:]

    func requireStringType() {
        requiresType = true
    }

    func requireArrayType(_ type: LLVMLowerability.ScalarType) {
        guard case .array = type else {
            return
        }
        requiredArrayTypes[type.llvmType] = type
    }

    func requireMalloc() {
        requiresMalloc = true
    }

    func requireFree() {
        requiresFree = true
    }

    func requireMemcpy() {
        requiresMemcpy = true
    }

    func requireTrap() {
        requiresTrap = true
    }

    func requireConstructType(_ layout: LLVMLowerability.ConstructLayout) {
        requiredConstructTypes[layout.identity] = layout
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
        guard requiresType || !requiredArrayTypes.isEmpty || requiresMalloc || requiresFree || requiresMemcpy || requiresTrap
            || !requiredConstructTypes.isEmpty
        else {
            return ""
        }
        var definitions: [String] = []
        if requiresType {
            definitions.append("%Range.String = type { ptr, i64 }")
        }
        for type in requiredArrayTypes.values.sorted(by: { $0.llvmType < $1.llvmType }) {
            definitions.append("\(type.llvmType) = type { ptr, i64, i64 }")
        }
        for layout in orderedConstructTypes() {
            let fieldTypes = layout.fields.map { $0.type.llvmType }.joined(separator: ", ")
            definitions.append(
                "\(LLVMLoweringEmitter.constructTypeName(identity: layout.identity, name: layout.name)) = type { \(fieldTypes) }"
            )
        }
        if requiresMalloc {
            definitions.append("declare ptr @malloc(i64)")
        }
        if requiresFree {
            definitions.append("declare void @free(ptr)")
        }
        if requiresMemcpy {
            definitions.append("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)")
        }
        if requiresTrap {
            definitions.append("declare void @llvm.trap() noreturn nounwind")
        }
        let globals = namesByValue.sorted { $0.value < $1.value }.map { value, name in
            let bytes = Array(value.utf8)
            return "\(name) = private unnamed_addr constant [\(bytes.count + 1) x i8] c\"\(llvmEscapedCString(bytes))\\00\", align 1"
        }
        return (definitions + globals).joined(separator: "\n")
    }

    private func orderedConstructTypes() -> [LLVMLowerability.ConstructLayout] {
        var result: [LLVMLowerability.ConstructLayout] = []
        var visited: Set<String> = []
        var visiting: Set<String> = []

        func visit(_ layout: LLVMLowerability.ConstructLayout) {
            guard !visited.contains(layout.identity), !visiting.contains(layout.identity) else {
                return
            }
            visiting.insert(layout.identity)
            for field in layout.fields {
                if case .construct(let identity, _) = field.type,
                    let dependency = requiredConstructTypes[identity]
                {
                    visit(dependency)
                }
            }
            visiting.remove(layout.identity)
            visited.insert(layout.identity)
            result.append(layout)
        }

        for layout in requiredConstructTypes.values.sorted(by: {
            ($0.name, $0.identity) < ($1.name, $1.identity)
        }) {
            visit(layout)
        }
        return result
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

    private enum LowerableMember: Equatable {
        case count
        case byteCount
        case element
        case isEmpty
        case append
        case update
        case field(index: Int, type: ScalarType)
    }

    struct CallableSymbol {
        let symbolName: String
        let signature: LLVMLowerability.ScalarSignature
    }

    private enum Symbol {
        case parameter(ScalarType)
        case stackSlot(pointer: String, type: ScalarType, mutable: Bool, ownsStorage: Bool)
    }

    private struct Value {
        let type: String
        let representation: String
        let scalarType: ScalarType?

        init(type: String, representation: String, scalarType: ScalarType? = nil) {
            self.type = type
            self.representation = representation
            self.scalarType = scalarType
        }
    }

    private var symbols: [String: Symbol]
    private let returnType: ScalarType
    private let callableSymbolsByName: [String: CallableSymbol]
    private let stringTable: LLVMStringTable
    private let constructLayouts: [String: LLVMLowerability.ConstructLayout]
    private let scalarTypes: [String: LLVMLowerability.ScalarType]
    private(set) var lines: [String] = []
    private var nextRegister = 0
    private var nextLabel = 0
    private var blockTerminated = false
    private var loopTargets: [(conditionLabel: String, endLabel: String)] = []

    init(
        signature: LLVMLowerability.ScalarSignature,
        parameters: [RangeFunctionParameter],
        callableSymbolsByName: [String: CallableSymbol],
        stringTable: LLVMStringTable,
        constructLayouts: [String: LLVMLowerability.ConstructLayout],
        scalarTypes: [String: LLVMLowerability.ScalarType]
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
        self.constructLayouts = constructLayouts
        self.scalarTypes = scalarTypes
    }

    mutating func emitBody(_ body: [LLVMStatement]) throws {
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

    private mutating func emitStatement(_ statement: LLVMStatement) throws {
        switch statement {
        case .emitted(let text):
            for record in StringyStatementRecord.records(in: text) {
                try emitStringyRecord(record)
                if blockTerminated {
                    break
                }
            }
            return
        case .ignored:
            return
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
            let converted = try convert(value, to: returnType)
            guard converted.type == returnType.llvmType else {
                throw LLVMLoweringError("LLVM return value must be \(returnType.llvmType).")
            }
            try emitOwnedLocalArrayFrees()
            emit("ret \(returnType.llvmType) \(converted.representation)")
            blockTerminated = true
        case .return(nil):
            throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
        case .expression(let expression):
            guard try emitLowerableSideEffectExpression(expression) else {
                throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
            }
        }
    }

    private mutating func emitStringyRecord(_ record: StringyStatementRecord) throws {
        switch record {
        case .returnStatement(let value?, let llvm):
            if concreteReturnLLVM(llvm) {
                try emitOwnedLocalArrayFrees()
                emit(llvm)
                blockTerminated = true
                return
            }
            let emittedValue = try emitExpression(value)
            let converted = try convert(emittedValue, to: returnType)
            guard converted.type == returnType.llvmType else {
                throw LLVMLoweringError("LLVM return value must be \(returnType.llvmType).")
            }
            try emitOwnedLocalArrayFrees()
            emit("ret \(returnType.llvmType) \(converted.representation)")
            blockTerminated = true
        case .returnStatement(nil, let llvm):
            guard concreteReturnLLVM(llvm) else {
                throw LLVMLoweringError("LLVM return record is missing a lowerable value.")
            }
            try emitOwnedLocalArrayFrees()
            emit(llvm)
            blockTerminated = true
        case .member(let kind, let name, let type, let value):
            try emitLocalBinding(
                LocalBindingDeclaration(
                    kind: kind == "state" ? .mutable : .constant,
                    name: name,
                    hasExplicitTypeAnnotation: true,
                    type: type,
                    expression: value
                )
            )
        case .assignment(let target, let value):
            try emitAssignment(target: .local(target), expression: value)
        case .expression(let expression):
            guard try emitLowerableSideEffectExpression(expression) else {
                throw LLVMLoweringError("LLVM lowering does not support expression record \(expression).")
            }
        case .whileLoop(let condition, let body):
            try emitStringyWhileLoop(condition: condition, body: body)
        case .conditional(let branches):
            try emitStringyConditional(branches)
        case .breakStatement:
            guard let target = loopTargets.last else {
                throw LLVMLoweringError("LLVM break requires an enclosing loop.")
            }
            emitBranch(to: target.endLabel)
        case .continueStatement:
            guard let target = loopTargets.last else {
                throw LLVMLoweringError("LLVM continue requires an enclosing loop.")
            }
            emitBranch(to: target.conditionLabel)
        }
    }

    private func concreteReturnLLVM(_ llvm: String) -> Bool {
        llvm == "ret void" || llvm.hasPrefix("ret \(returnType.llvmType) ")
    }

    private mutating func emitLocalBinding(_ declaration: LocalBindingDeclaration) throws {
        guard let scalarType = ScalarType(
            typeReference: declaration.type,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        ) else {
            throw LLVMLoweringError("LLVM local binding '\(declaration.name)' must be LLVM lowerable.")
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
            mutable: isMutable(declaration.kind),
            ownsStorage: isOwnedArrayAllocation(declaration.expression)
        )
    }

    private mutating func emitAssignment(
        target: AssignmentTarget,
        expression: RangeCompiler.Expression
    ) throws {
        guard case .local(let name) = target else {
            throw LLVMLoweringError("LLVM assignment currently supports local state only.")
        }
        guard case .stackSlot(let pointer, let type, let mutable, _) = symbols[name],
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

    private mutating func emitWhileLoop(
        condition: RangeCompiler.Expression,
        body: [LLVMStatement]
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

    private mutating func emitStringyWhileLoop(
        condition: RangeCompiler.Expression,
        body: [StringyStatementRecord]
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
        for record in body {
            try emitStringyRecord(record)
            if blockTerminated {
                break
            }
        }
        if !blockTerminated {
            emitBranch(to: conditionLabel)
        }

        emitLabel(endLabel)
    }

    private mutating func emitConditional(_ branches: [LLVMConditionalBranch]) throws {
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

    private mutating func emitStringyConditional(_ branches: [StringyConditionalBranch]) throws {
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
            for record in branch.body {
                try emitStringyRecord(record)
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

    private mutating func emitStatements(_ statements: [LLVMStatement]) throws {
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
            return Value(type: "i64", representation: String(value), scalarType: .defaultInt)
        case .double(let value):
            return Value(type: "double", representation: llvmDoubleLiteral(value), scalarType: .float)
        case .boolean(let value):
            return Value(type: "i1", representation: value ? "1" : "0", scalarType: .bool)
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
            return Value(type: "%Range.String", representation: countRegister, scalarType: .string)
        case .identifier(let name):
            if let member = try emitLowerableMemberAccess(name: name) {
                return member
            }
            guard let symbol = symbols[name] else {
                throw LLVMLoweringError("LLVM lowering cannot resolve identifier '\(name)'.")
            }
            switch symbol {
            case .parameter(let type):
                return Value(type: type.llvmType, representation: "%\(name)", scalarType: type)
            case .stackSlot(let pointer, let type, _, _):
                let register = freshRegister()
                emit("\(register) = load \(type.llvmType), ptr \(pointer)")
                return Value(type: type.llvmType, representation: register, scalarType: type)
            }
        case .unary(.not, let expression):
            let value = try emitExpression(expression)
            guard value.type == "i1" else {
                throw LLVMLoweringError("LLVM ! operand must be i1.")
            }
            let register = freshRegister()
            emit("\(register) = xor i1 \(value.representation), true")
            return Value(type: "i1", representation: register, scalarType: .bool)
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
            return Value(
                type: resultType,
                representation: register,
                scalarType: scalarType(forLLVMType: resultType)
            )
        case .call(let name, let arguments):
            if let allocation = try emitLowerableArrayAllocation(
                name: name,
                arguments: arguments
            ) {
                return allocation
            }
            if let scalar = try emitLowerableScalarConstructor(name: name, arguments: arguments) {
                return scalar
            }
            if let construction = try emitLowerableConstructInitialization(
                name: name,
                arguments: arguments
            ) {
                return construction
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
            return Value(
                type: callable.signature.returnType.llvmType,
                representation: register,
                scalarType: callable.signature.returnType
            )
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

        let base = try emitIdentifierOrMemberAccess(named: baseName)
        if let constructField = constructFieldAccess(baseType: base.type, memberName: memberName) {
            let register = freshRegister()
            emit(
                "\(register) = extractvalue \(base.type) \(base.representation), \(constructField.index)"
            )
            return Value(
                type: constructField.type.llvmType,
                representation: register,
                scalarType: constructField.type
            )
        }
        guard base.type == "%Range.String" || base.scalarType?.arrayElementType != nil else {
            return nil
        }
        guard let member = lowerableMemberAccess(name: memberName) else {
            return nil
        }

        let countRegister = freshRegister()
        emit("\(countRegister) = extractvalue \(base.type) \(base.representation), 1")
        switch member {
        case .count:
            return Value(type: "i64", representation: countRegister, scalarType: .defaultInt)
        case .byteCount:
            return Value(type: "i64", representation: countRegister, scalarType: .defaultInt)
        case .element:
            return nil
        case .append:
            return nil
        case .update:
            return nil
        case .field:
            return nil
        case .isEmpty:
            let resultRegister = freshRegister()
            emit("\(resultRegister) = icmp eq i64 \(countRegister), 0")
            return Value(type: "i1", representation: resultRegister, scalarType: .bool)
        }
    }

    private mutating func emitLowerableConstructInitialization(
        name: String,
        arguments: [CallArgument]
    ) throws -> Value? {
        guard let layout = uniqueConstructLayout(named: name) else {
            return nil
        }
        var current = "undef"
        for (index, field) in layout.fields.enumerated() {
            guard let expression = argumentValue(labeled: field.name, at: index, in: arguments) else {
                throw LLVMLoweringError("LLVM construct \(name) expects field \(field.name).")
            }
            let rawValue = try emitExpression(expression)
            let value = try convert(rawValue, to: field.type)
            guard value.type == field.type.llvmType else {
                throw LLVMLoweringError("LLVM construct field \(field.name) must be \(field.type.llvmType).")
            }
            let register = freshRegister()
            let constructType = ScalarType.construct(identity: layout.identity, name: layout.name)
                .llvmType
            emit(
                "\(register) = insertvalue \(constructType) \(current), \(field.type.llvmType) \(value.representation), \(index)"
            )
            current = register
        }
        return Value(
            type: ScalarType.construct(identity: layout.identity, name: layout.name).llvmType,
            representation: current,
            scalarType: .construct(identity: layout.identity, name: layout.name)
        )
    }

    private mutating func emitLowerableScalarConstructor(
        name: String,
        arguments: [CallArgument]
    ) throws -> Value? {
        guard arguments.count == 1, arguments[0].label == nil else {
            return nil
        }
        let target: ScalarType?
        switch name {
        case "Int":
            target = scalarTypes["Int"] ?? .defaultInt
        case "Bool":
            target = scalarTypes["Bool"] ?? .bool
        case "Float":
            target = .float
        case "String":
            target = .string
        default:
            target = ScalarType(
                typeReference: .named(name),
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            )
        }
        guard let target else {
            return nil
        }

        let rawValue = try emitExpression(arguments[0].value)
        let converted = try convert(rawValue, to: target)
        guard converted.type == target.llvmType else {
            throw LLVMLoweringError("LLVM scalar construction \(name) must produce \(target.llvmType).")
        }
        return converted
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
            throw LLVMLoweringError("LLVM Array.element expects one index argument.")
        }

        let base = try emitIdentifier(named: baseName)
        guard let arrayType = base.scalarType,
            case .array(let elementType) = arrayType
        else {
            return nil
        }
        let rawIndex = try emitExpression(arguments[0].value)
        let index = try convert(value: rawIndex, toLLVMType: "i64")
        guard index.type == "i64" else {
            throw LLVMLoweringError("LLVM Array.element index must be i64.")
        }

        let checkedIndex = try emitArrayBoundsCheck(
            array: base,
            index: index,
            operation: "element"
        )
        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = extractvalue \(arrayType.llvmType) \(base.representation), 0")
        let elementPointerRegister = freshRegister()
        emit(
            "\(elementPointerRegister) = getelementptr inbounds \(elementType.llvmType), ptr \(pointerRegister), i64 \(checkedIndex.representation)"
        )
        let valueRegister = freshRegister()
        emit("\(valueRegister) = load \(elementType.llvmType), ptr \(elementPointerRegister)")
        return Value(type: elementType.llvmType, representation: valueRegister, scalarType: elementType)
    }

    private mutating func emitLowerableArrayAllocation(
        name: String,
        arguments: [CallArgument]
    ) throws -> Value? {
        guard let elementName = arrayElementName(from: name),
            let elementType = ScalarType(typeReference: .named(elementName), constructLayouts: constructLayouts, scalarTypes: scalarTypes)
        else {
            return nil
        }
        let arrayType = ScalarType.array(element: elementType)
        if arguments.isEmpty {
            stringTable.requireArrayType(arrayType)
            let pointerValueRegister = freshRegister()
            emit(
                "\(pointerValueRegister) = insertvalue \(arrayType.llvmType) undef, ptr null, 0"
            )
            let countValueRegister = freshRegister()
            emit(
                "\(countValueRegister) = insertvalue \(arrayType.llvmType) \(pointerValueRegister), i64 0, 1"
            )
            let capacityValueRegister = freshRegister()
            emit(
                "\(capacityValueRegister) = insertvalue \(arrayType.llvmType) \(countValueRegister), i64 0, 2"
            )
            return Value(type: arrayType.llvmType, representation: capacityValueRegister, scalarType: arrayType)
        }
        guard arguments.count == 1 else {
            throw LLVMLoweringError("LLVM Array allocation expects one capacity argument.")
        }
        guard arguments[0].label == "capacity" || arguments[0].label == nil else {
            throw LLVMLoweringError("LLVM Array allocation expects a capacity argument.")
        }

        let rawCapacity = try emitExpression(arguments[0].value)
        let capacity = try convert(value: rawCapacity, toLLVMType: "i64")
        guard capacity.type == "i64" else {
            throw LLVMLoweringError("LLVM Array allocation capacity must be i64.")
        }

        stringTable.requireArrayType(arrayType)
        stringTable.requireMalloc()
        let byteCountRegister = freshRegister()
        emit("\(byteCountRegister) = mul i64 \(capacity.representation), \(arrayType.arrayElementByteStride)")
        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = call ptr @malloc(i64 \(byteCountRegister))")
        let pointerValueRegister = freshRegister()
        emit(
            "\(pointerValueRegister) = insertvalue \(arrayType.llvmType) undef, ptr \(pointerRegister), 0"
        )
        let countValueRegister = freshRegister()
        emit(
            "\(countValueRegister) = insertvalue \(arrayType.llvmType) \(pointerValueRegister), i64 0, 1"
        )
        let capacityValueRegister = freshRegister()
        emit(
            "\(capacityValueRegister) = insertvalue \(arrayType.llvmType) \(countValueRegister), i64 \(capacity.representation), 2"
        )
        return Value(type: arrayType.llvmType, representation: capacityValueRegister, scalarType: arrayType)
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
        switch memberName {
        case "append":
            try emitLowerableArrayAppend(baseName: baseName, arguments: arguments)
            return true
        case "update":
            try emitLowerableArrayUpdate(baseName: baseName, arguments: arguments)
            return true
        default:
            return false
        }
    }

    private mutating func emitLowerableArrayAppend(
        baseName: String,
        arguments: [CallArgument]
    ) throws {
        guard arguments.count == 1 else {
            throw LLVMLoweringError("LLVM Array.append expects one element argument.")
        }
        guard let elementExpression = argumentValue(labeled: "element", at: 0, in: arguments)
        else {
            throw LLVMLoweringError("LLVM Array.append expects an element argument.")
        }

        let base = try emitMutableArray(named: baseName)
        guard let arrayType = base.value.scalarType,
            let elementType = arrayType.arrayElementType
        else {
            throw LLVMLoweringError("LLVM Array.append requires an Array base.")
        }
        let rawElement = try emitExpression(elementExpression)
        let element = try convert(rawElement, to: elementType)
        guard element.type == elementType.llvmType else {
            throw LLVMLoweringError("LLVM Array.append element must be \(elementType.llvmType).")
        }

        let countRegister = freshRegister()
        emit("\(countRegister) = extractvalue \(arrayType.llvmType) \(base.value.representation), 1")
        let capacityRegister = freshRegister()
        emit("\(capacityRegister) = extractvalue \(arrayType.llvmType) \(base.value.representation), 2")
        let canAppendRegister = freshRegister()
        emit("\(canAppendRegister) = icmp slt i64 \(countRegister), \(capacityRegister)")

        let labelID = freshLabelID()
        let appendLabel = "array.append.\(labelID)"
        let growLabel = "array.grow.\(labelID)"
        let endLabel = "array.end.\(labelID)"
        emit("br i1 \(canAppendRegister), label %\(appendLabel), label %\(growLabel)")
        blockTerminated = true

        emitLabel(growLabel)
        let grownArray = try emitArrayGrowth(
            array: base.value,
            count: countRegister,
            capacity: capacityRegister
        )
        emit("store \(arrayType.llvmType) \(grownArray.representation), ptr \(base.pointer)")
        emitBranch(to: appendLabel)

        emitLabel(appendLabel)
        let currentArrayRegister = freshRegister()
        emit("\(currentArrayRegister) = load \(arrayType.llvmType), ptr \(base.pointer)")
        let currentArray = Value(
            type: arrayType.llvmType,
            representation: currentArrayRegister,
            scalarType: arrayType
        )
        let currentCountRegister = freshRegister()
        emit("\(currentCountRegister) = extractvalue \(arrayType.llvmType) \(currentArray.representation), 1")
        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = extractvalue \(arrayType.llvmType) \(currentArray.representation), 0")
        let elementPointerRegister = freshRegister()
        emit(
            "\(elementPointerRegister) = getelementptr inbounds \(elementType.llvmType), ptr \(pointerRegister), i64 \(currentCountRegister)"
        )
        emit("store \(elementType.llvmType) \(element.representation), ptr \(elementPointerRegister)")
        let nextCountRegister = freshRegister()
        emit("\(nextCountRegister) = add i64 \(currentCountRegister), 1")
        let updatedArrayRegister = freshRegister()
        emit(
            "\(updatedArrayRegister) = insertvalue \(arrayType.llvmType) \(currentArray.representation), i64 \(nextCountRegister), 1"
        )
        emit("store \(arrayType.llvmType) \(updatedArrayRegister), ptr \(base.pointer)")
        emitBranch(to: endLabel)

        emitLabel(endLabel)
    }

    private mutating func emitArrayGrowth(
        array: Value,
        count: String,
        capacity: String
    ) throws -> Value {
        guard let arrayType = array.scalarType,
            case .array = arrayType
        else {
            throw LLVMLoweringError("LLVM Array growth requires Array.")
        }

        stringTable.requireMalloc()
        stringTable.requireFree()
        stringTable.requireMemcpy()

        let doubledCapacityRegister = freshRegister()
        emit("\(doubledCapacityRegister) = mul i64 \(capacity), 2")
        let capacityIsZeroRegister = freshRegister()
        emit("\(capacityIsZeroRegister) = icmp eq i64 \(capacity), 0")
        let newCapacityRegister = freshRegister()
        emit(
            "\(newCapacityRegister) = select i1 \(capacityIsZeroRegister), i64 1, i64 \(doubledCapacityRegister)"
        )
        let byteCountRegister = freshRegister()
        emit("\(byteCountRegister) = mul i64 \(newCapacityRegister), \(arrayType.arrayElementByteStride)")
        let newPointerRegister = freshRegister()
        emit("\(newPointerRegister) = call ptr @malloc(i64 \(byteCountRegister))")
        let oldPointerRegister = freshRegister()
        emit("\(oldPointerRegister) = extractvalue \(arrayType.llvmType) \(array.representation), 0")
        let hasElementsRegister = freshRegister()
        emit("\(hasElementsRegister) = icmp ne i64 \(count), 0")
        let labelID = freshLabelID()
        let copyLabel = "array.grow.copy.\(labelID)"
        let finishLabel = "array.grow.finish.\(labelID)"
        emit("br i1 \(hasElementsRegister), label %\(copyLabel), label %\(finishLabel)")
        blockTerminated = true

        emitLabel(copyLabel)
        let copiedByteCountRegister = freshRegister()
        emit("\(copiedByteCountRegister) = mul i64 \(count), 8")
        emit(
            "call void @llvm.memcpy.p0.p0.i64(ptr \(newPointerRegister), ptr \(oldPointerRegister), i64 \(copiedByteCountRegister), i1 false)"
        )
        emit("call void @free(ptr \(oldPointerRegister))")
        emitBranch(to: finishLabel)

        emitLabel(finishLabel)
        let pointerArrayRegister = freshRegister()
        emit(
            "\(pointerArrayRegister) = insertvalue \(arrayType.llvmType) \(array.representation), ptr \(newPointerRegister), 0"
        )
        let capacityArrayRegister = freshRegister()
        emit(
            "\(capacityArrayRegister) = insertvalue \(arrayType.llvmType) \(pointerArrayRegister), i64 \(newCapacityRegister), 2"
        )
        return Value(type: arrayType.llvmType, representation: capacityArrayRegister, scalarType: arrayType)
    }

    private mutating func emitLowerableArrayUpdate(
        baseName: String,
        arguments: [CallArgument]
    ) throws {
        guard arguments.count == 2 else {
            throw LLVMLoweringError("LLVM Array.update expects element and index arguments.")
        }

        let base = try emitIdentifier(named: baseName)
        guard let arrayType = base.scalarType,
            let elementType = arrayType.arrayElementType
        else {
            throw LLVMLoweringError("LLVM Array.update requires an Array base.")
        }
        guard let elementExpression = argumentValue(labeled: "element", at: 0, in: arguments),
            let indexExpression = argumentValue(labeled: "index", at: 1, in: arguments)
        else {
            throw LLVMLoweringError("LLVM Array.update expects element and index arguments.")
        }

        let rawElement = try emitExpression(elementExpression)
        let element = try convert(rawElement, to: elementType)
        guard element.type == elementType.llvmType else {
            throw LLVMLoweringError("LLVM Array.update element must be \(elementType.llvmType).")
        }
        let rawIndex = try emitExpression(indexExpression)
        let index = try convert(value: rawIndex, toLLVMType: "i64")
        guard index.type == "i64" else {
            throw LLVMLoweringError("LLVM Array.update index must be i64.")
        }

        let checkedIndex = try emitArrayBoundsCheck(
            array: base,
            index: index,
            operation: "update"
        )
        let pointerRegister = freshRegister()
        emit("\(pointerRegister) = extractvalue \(arrayType.llvmType) \(base.representation), 0")
        let elementPointerRegister = freshRegister()
        emit(
            "\(elementPointerRegister) = getelementptr inbounds \(elementType.llvmType), ptr \(pointerRegister), i64 \(checkedIndex.representation)"
        )
        emit("store \(elementType.llvmType) \(element.representation), ptr \(elementPointerRegister)")
    }

    private mutating func emitArrayBoundsCheck(
        array: Value,
        index: Value,
        operation: String
    ) throws -> Value {
        guard let arrayType = array.scalarType,
            case .array = arrayType,
            index.type == "i64"
        else {
            throw LLVMLoweringError("LLVM Array bounds check requires Array and i64 index.")
        }

        let countRegister = freshRegister()
        emit("\(countRegister) = extractvalue \(arrayType.llvmType) \(array.representation), 1")
        let nonNegativeRegister = freshRegister()
        emit("\(nonNegativeRegister) = icmp sge i64 \(index.representation), 0")
        let belowCountRegister = freshRegister()
        emit("\(belowCountRegister) = icmp slt i64 \(index.representation), \(countRegister)")
        let inBoundsRegister = freshRegister()
        emit("\(inBoundsRegister) = and i1 \(nonNegativeRegister), \(belowCountRegister)")

        let labelID = freshLabelID()
        let okLabel = "array.\(operation).bounds.ok.\(labelID)"
        let trapLabel = "array.\(operation).bounds.trap.\(labelID)"
        emit("br i1 \(inBoundsRegister), label %\(okLabel), label %\(trapLabel)")
        blockTerminated = true

        stringTable.requireTrap()
        emitLabel(trapLabel)
        emit("call void @llvm.trap()")
        emit("unreachable")
        blockTerminated = true

        emitLabel(okLabel)
        return index
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
        case "append":
            return .append
        case "element":
            return .element
        case "update":
            return .update
        default:
            return nil
        }
    }

    private mutating func emitMutableArray(named name: String) throws -> (
        pointer: String, value: Value
    ) {
        guard case .stackSlot(let pointer, let type, let mutable, _) = symbols[name],
            case .array = type,
            mutable
        else {
            throw LLVMLoweringError("LLVM Array.append target '\(name)' is not mutable local state.")
        }
        let register = freshRegister()
        emit("\(register) = load \(type.llvmType), ptr \(pointer)")
        return (pointer, Value(type: type.llvmType, representation: register, scalarType: type))
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

    private func constructFieldAccess(baseType: String, memberName: String) -> (
        index: Int, type: ScalarType
    )? {
        for layout in constructLayouts.values
            where ScalarType.construct(identity: layout.identity, name: layout.name).llvmType == baseType
        {
            if let field = layout.field(named: memberName) {
                return (field.index, field.field.type)
            }
        }
        return nil
    }

    private func uniqueConstructLayout(named name: String) -> LLVMLowerability.ConstructLayout? {
        let matches = constructLayouts.values.filter { $0.name == name }
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private mutating func emitIdentifier(named name: String) throws -> Value {
        guard let symbol = symbols[name] else {
            throw LLVMLoweringError("LLVM lowering cannot resolve identifier '\(name)'.")
        }
        switch symbol {
        case .parameter(let type):
            return Value(type: type.llvmType, representation: "%\(name)", scalarType: type)
        case .stackSlot(let pointer, let type, _, _):
            let register = freshRegister()
            emit("\(register) = load \(type.llvmType), ptr \(pointer)")
            return Value(type: type.llvmType, representation: register, scalarType: type)
        }
    }

    private mutating func emitIdentifierOrMemberAccess(named name: String) throws -> Value {
        if let member = try emitLowerableMemberAccess(name: name) {
            return member
        }
        return try emitIdentifier(named: name)
    }

    private func isOwnedArrayAllocation(_ expression: RangeCompiler.Expression) -> Bool {
        guard case .call(let name, let arguments) = expression else {
            return false
        }
        return arrayElementName(from: name) != nil
            && arguments.count == 1
            && (arguments[0].label == "capacity" || arguments[0].label == nil)
    }

    private mutating func emitOwnedLocalArrayFrees() throws {
        guard returnType.arrayElementType == nil else {
            return
        }
        let ownedArrays = symbols.sorted { $0.key < $1.key }.compactMap { entry -> (pointer: String, type: ScalarType)? in
            guard case .stackSlot(let pointer, let type, _, let ownsStorage) = entry.value,
                case .array = type,
                ownsStorage
            else {
                return nil
            }
            return (pointer, type)
        }
        guard !ownedArrays.isEmpty else {
            return
        }
        stringTable.requireFree()
        for (pointer, type) in ownedArrays {
            let arrayRegister = freshRegister()
            emit("\(arrayRegister) = load \(type.llvmType), ptr \(pointer)")
            let storageRegister = freshRegister()
            emit("\(storageRegister) = extractvalue \(type.llvmType) \(arrayRegister), 0")
            emit("call void @free(ptr \(storageRegister))")
        }
    }

    private func arrayElementName(from callName: String) -> String? {
        guard callName.hasPrefix("Array<"), callName.hasSuffix(">") else {
            return nil
        }
        let start = callName.index(callName.startIndex, offsetBy: "Array<".count)
        let end = callName.index(before: callName.endIndex)
        return String(callName[start..<end])
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
            lhsValue: lhsValue,
            rhsValue: rhsValue
        )
        let convertedLHS = try convert(lhsValue, to: instruction.operandScalarType)
        let convertedRHS = try convert(rhsValue, to: instruction.operandScalarType)
        let register = freshRegister()
        emit(
            "\(register) = \(instruction.mnemonic) \(instruction.operandType) \(convertedLHS.representation), \(convertedRHS.representation)"
        )
        return Value(
            type: instruction.resultType,
            representation: register,
            scalarType: instruction.resultScalarType
        )
    }

    private func ternaryLLVMType(_ lhsType: String, _ rhsType: String) throws -> String {
        if lhsType == rhsType {
            return lhsType
        }
        if (isLLVMIntegerType(lhsType) && rhsType == "double")
            || (lhsType == "double" && isLLVMIntegerType(rhsType))
        {
            return "double"
        }
        throw LLVMLoweringError("LLVM ternary branches must have compatible scalar types.")
    }

    private mutating func convert(_ value: Value, to scalarType: ScalarType) throws -> Value {
        if value.scalarType == scalarType, value.type == scalarType.llvmType {
            return value
        }
        if case .int(let actualBits, let actualSigned) = value.scalarType,
            case .int(let expectedBits, _) = scalarType
        {
            if actualBits == expectedBits {
                return Value(
                    type: scalarType.llvmType,
                    representation: value.representation,
                    scalarType: scalarType
                )
            }
            let register = freshRegister()
            if actualBits < expectedBits {
                emit(
                    "\(register) = \(actualSigned ? "sext" : "zext") \(value.type) \(value.representation) to \(scalarType.llvmType)"
                )
            } else {
                emit(
                    "\(register) = trunc \(value.type) \(value.representation) to \(scalarType.llvmType)"
                )
            }
            return Value(type: scalarType.llvmType, representation: register, scalarType: scalarType)
        }
        if value.scalarType?.isInteger == true, scalarType == .float {
            let register = freshRegister()
            let mnemonic = value.scalarType?.isSignedInteger == false ? "uitofp" : "sitofp"
            emit("\(register) = \(mnemonic) \(value.type) \(value.representation) to double")
            return Value(type: "double", representation: register, scalarType: .float)
        }
        return try convert(value: value, toLLVMType: scalarType.llvmType)
    }

    private mutating func convert(value: Value, toLLVMType llvmType: String) throws -> Value {
        if value.type == llvmType {
            return value
        }
        if value.scalarType?.isInteger == true, llvmType == "double" {
            let register = freshRegister()
            let mnemonic = value.scalarType?.isSignedInteger == false ? "uitofp" : "sitofp"
            emit("\(register) = \(mnemonic) \(value.type) \(value.representation) to double")
            return Value(type: "double", representation: register, scalarType: .float)
        }
        return value
    }

    private func scalarType(forLLVMType llvmType: String) -> ScalarType? {
        if llvmType == "double" {
            return .float
        }
        if llvmType == "i1" {
            return .bool
        }
        guard isLLVMIntegerType(llvmType),
            let bits = Int(llvmType.dropFirst())
        else {
            return nil
        }
        return .int(bits: bits, signed: true)
    }

    private func commonIntegerScalarType(_ lhs: Value, _ rhs: Value) -> ScalarType? {
        guard case .int(let lhsBits, let lhsSigned) = lhs.scalarType,
            case .int(let rhsBits, let rhsSigned) = rhs.scalarType
        else {
            return nil
        }
        if lhs.scalarType == .defaultInt, Int(lhs.representation) != nil {
            return rhs.scalarType
        }
        if rhs.scalarType == .defaultInt, Int(rhs.representation) != nil {
            return lhs.scalarType
        }
        if lhsBits == rhsBits {
            return .int(bits: lhsBits, signed: lhsSigned && rhsSigned)
        }
        if lhsBits > rhsBits {
            return lhs.scalarType
        }
        return rhs.scalarType
    }

    private func llvmInstruction(
        for operatorSymbol: BinaryOperator,
        lhsValue: Value,
        rhsValue: Value
    ) throws -> (
        mnemonic: String,
        operandType: String,
        operandScalarType: ScalarType,
        resultType: String,
        resultScalarType: ScalarType
    ) {
        let lhsType = lhsValue.type
        let rhsType = rhsValue.type
        switch operatorSymbol {
        case .addition, .subtraction, .multiplication, .division:
            if lhsType == "double" || rhsType == "double" {
                return (floatArithmeticMnemonic(for: operatorSymbol), "double", .float, "double", .float)
            }
            guard let intType = commonIntegerScalarType(lhsValue, rhsValue) else {
                throw LLVMLoweringError(
                    "LLVM \(operatorSymbol.rawValue) operands must be numeric.")
            }
            return (
                intArithmeticMnemonic(for: operatorSymbol, signed: intType.isSignedInteger != false),
                intType.llvmType,
                intType,
                intType.llvmType,
                intType
            )
        case .remainder:
            guard let intType = commonIntegerScalarType(lhsValue, rhsValue) else {
                throw LLVMLoweringError("LLVM % operands must be integer.")
            }
            return (intType.isSignedInteger == false ? "urem" : "srem", intType.llvmType, intType, intType.llvmType, intType)
        case .equal, .notEqual:
            if lhsType == "double" || rhsType == "double" {
                return (floatComparisonMnemonic(for: operatorSymbol), "double", .float, "i1", .bool)
            }
            if let intType = commonIntegerScalarType(lhsValue, rhsValue) {
                return (intComparisonMnemonic(for: operatorSymbol, signed: true), intType.llvmType, intType, "i1", .bool)
            }
            if lhsType == "i1", rhsType == "i1" {
                return (intComparisonMnemonic(for: operatorSymbol, signed: true), "i1", .bool, "i1", .bool)
            }
            throw LLVMLoweringError("LLVM \(operatorSymbol.rawValue) operands must match.")
        case .less, .lessEqual, .greater, .greaterEqual:
            if lhsType == "double" || rhsType == "double" {
                return (floatComparisonMnemonic(for: operatorSymbol), "double", .float, "i1", .bool)
            }
            guard let intType = commonIntegerScalarType(lhsValue, rhsValue) else {
                throw LLVMLoweringError(
                    "LLVM \(operatorSymbol.rawValue) operands must be numeric.")
            }
            return (
                intComparisonMnemonic(
                    for: operatorSymbol,
                    signed: intType.isSignedInteger != false
                ),
                intType.llvmType,
                intType,
                "i1",
                .bool
            )
        case .and:
            guard lhsType == "i1", rhsType == "i1" else {
                throw LLVMLoweringError("LLVM && operands must be i1.")
            }
            return ("and", "i1", .bool, "i1", .bool)
        case .or:
            guard lhsType == "i1", rhsType == "i1" else {
                throw LLVMLoweringError("LLVM || operands must be i1.")
            }
            return ("or", "i1", .bool, "i1", .bool)
        case .nilCoalescing:
            throw LLVMLoweringError(
                "LLVM lowering does not support operator '\(operatorSymbol.rawValue)' yet.")
        case .rangeUntil, .closedRange:
            throw LLVMLoweringError(
                "LLVM lowering does not support operator '\(operatorSymbol.rawValue)' yet.")
        }
    }

    private func intArithmeticMnemonic(for operatorSymbol: BinaryOperator, signed: Bool) -> String {
        switch operatorSymbol {
        case .addition:
            return "add"
        case .subtraction:
            return "sub"
        case .multiplication:
            return "mul"
        case .division:
            return signed ? "sdiv" : "udiv"
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

    private func intComparisonMnemonic(for operatorSymbol: BinaryOperator, signed: Bool) -> String {
        switch operatorSymbol {
        case .equal:
            return "icmp eq"
        case .notEqual:
            return "icmp ne"
        case .less:
            return signed ? "icmp slt" : "icmp ult"
        case .lessEqual:
            return signed ? "icmp sle" : "icmp ule"
        case .greater:
            return signed ? "icmp sgt" : "icmp ugt"
        case .greaterEqual:
            return signed ? "icmp sge" : "icmp uge"
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
