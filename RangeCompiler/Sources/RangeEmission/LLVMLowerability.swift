import RangeCompiler

enum LLVMLowerability {
    struct ConstructLayout: Equatable {
        struct Field: Equatable {
            var name: String
            var type: ScalarType
        }

        var identity: String
        var name: String
        var fields: [Field]

        func field(named name: String) -> (index: Int, field: Field)? {
            for (index, field) in fields.enumerated() where field.name == name {
                return (index, field)
            }
            return nil
        }
    }

    struct ScalarSignature {
        var parameters: [ScalarType]
        var returnType: ScalarType
    }

    indirect enum ScalarType: Equatable, Sendable {
        case int(bits: Int, signed: Bool)
        case bool
        case float
        case string
        case array(element: ScalarType)
        case construct(identity: String, name: String)

        init?(
            typeReference: TypeReference,
            constructLayouts: [String: ConstructLayout] = [:],
            scalarTypes: [String: ScalarType] = [:]
        ) {
            switch typeReference {
            case .named("Int"):
                self = scalarTypes["Int"] ?? .defaultInt
            case .generic(let base, let arguments) where base == .named("Int"):
                guard let type = Self.intType(arguments: arguments) else {
                    return nil
                }
                self = type
            case .named("Bool"):
                self = scalarTypes["Bool"] ?? .bool
            case .named("Float"):
                self = .float
            case .named("String"):
                self = .string
            case .array(let element):
                guard let elementType = ScalarType(
                    typeReference: element,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ) else {
                    return nil
                }
                self = .array(element: elementType)
            case .named(let name):
                if let scalarType = scalarTypes[name] {
                    self = scalarType
                    return
                }
                let matchingLayouts = constructLayouts.values.filter {
                    $0.name == name
                }
                if matchingLayouts.count == 1, let layout = matchingLayouts.first {
                    self = .construct(identity: layout.identity, name: layout.name)
                    return
                }
                if let type = Self.intType(displayName: name) {
                    self = type
                    return
                }
                return nil
            case .member, .generic, .function, .optional, .variadic:
                return nil
            }
        }

        static let defaultInt = ScalarType.int(bits: 64, signed: true)

        static func intType(arguments: [TypeReference]) -> ScalarType? {
            guard let bitsArgument = arguments.first,
                let bits = Int(bitsArgument.displayName),
                bits > 0
            else {
                return nil
            }
            let signed = !arguments.dropFirst().contains {
                $0.displayName == ".unsigned" || $0.displayName.hasSuffix(".unsigned")
                    || $0.displayName == "unsigned"
            }
            return .int(bits: bits, signed: signed)
        }

        static func intType(displayName: String) -> ScalarType? {
            guard displayName.hasPrefix("Int<"), displayName.hasSuffix(">") else {
                return nil
            }
            let start = displayName.index(displayName.startIndex, offsetBy: 4)
            let end = displayName.index(before: displayName.endIndex)
            let arguments = displayName[start..<end].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let bitsText = arguments.first, let bits = Int(bitsText), bits > 0 else {
                return nil
            }
            let signed = !arguments.dropFirst().contains {
                $0 == ".unsigned" || $0.hasSuffix(".unsigned") || $0 == "unsigned"
            }
            return .int(bits: bits, signed: signed)
        }

        init?(integerMacroValue value: String) {
            if value.hasPrefix("integer|"),
                let bitsText = Self.recordField("bits", in: value),
                let bits = Int(bitsText),
                bits > 0
            {
                let signedness = Self.recordField("signedness", in: value) ?? "signed"
                self = .int(bits: bits, signed: signedness != "unsigned")
                return
            }

            guard value.hasPrefix("i") else {
                return nil
            }
            let digits = value.dropFirst()
            guard !digits.isEmpty,
                digits.allSatisfy(\.isNumber),
                let bits = Int(String(digits)),
                bits > 0
            else {
                return nil
            }
            self = .int(bits: bits, signed: true)
        }

        init?(boolMacroValue value: String) {
            guard value == "i1" || value == "bool" else {
                return nil
            }
            self = .bool
        }

        private static func recordField(_ name: String, in value: String) -> String? {
            let prefix = "\(name)="
            guard let range = value.range(of: prefix) else {
                return nil
            }
            let afterPrefix = value[range.upperBound...]
            if let end = afterPrefix.firstIndex(of: "|") {
                return String(afterPrefix[..<end])
            }
            return String(afterPrefix)
        }
    }

    static func scalarTypes(from declarations: [ConstructDeclaration]) -> [String: ScalarType] {
        declarations.reduce(into: [:]) { result, declaration in
            if let value = declaration.macros.first(where: { $0.name == "integer" })?
                .evaluatedStringValue,
                let scalarType = ScalarType(integerMacroValue: value)
            {
                result[declaration.name] = scalarType
            }

            if let value = declaration.macros.first(where: { $0.name == "bool" })?
                .evaluatedStringValue,
                let scalarType = ScalarType(boolMacroValue: value)
            {
                result[declaration.name] = scalarType
            }
        }
    }

    static func constructLayouts(from declarations: [ConstructDeclaration]) -> [String: ConstructLayout] {
        let nameCounts = declarations.reduce(into: [:]) { counts, declaration in
            counts[declaration.name, default: 0] += 1
        }
        var seenNames: [String: Int] = [:]
        let candidates = declarations.map { declaration -> (identity: String, declaration: ConstructDeclaration) in
            let seen = seenNames[declaration.name, default: 0] + 1
            seenNames[declaration.name] = seen
            let identity = constructIdentity(
                for: declaration,
                ordinal: nameCounts[declaration.name, default: 0] == 1 ? nil : seen
            )
            return (identity, declaration)
        }

        let declarationsByIdentity = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.identity, $0.declaration) }
        )
        let identitiesByName = candidates.reduce(into: [String: [String]]()) { result, candidate in
            result[candidate.declaration.name, default: []].append(candidate.identity)
        }
        var builtLayouts: [String: ConstructLayout] = [:]
        var visiting: Set<String> = []

        func build(_ identity: String) -> ConstructLayout? {
            if let layout = builtLayouts[identity] {
                return layout
            }
            guard !visiting.contains(identity),
                let declaration = declarationsByIdentity[identity]
            else {
                return nil
            }
            visiting.insert(identity)
            defer { visiting.remove(identity) }

            guard declaration.genericParameters.isEmpty,
                declaration.states.isEmpty,
                declaration.bindings.isEmpty,
                declaration.deriveds.isEmpty
            else {
                return nil
            }

            let fields = declaration.values.compactMap { value -> ConstructLayout.Field? in
                guard let type = constructFieldType(
                    named: value.typeName,
                    identitiesByName: identitiesByName,
                    build: build
                ) else {
                    return nil
                }
                return ConstructLayout.Field(name: value.name, type: type)
            }
            guard fields.count == declaration.values.count else {
                return nil
            }

            let layout = ConstructLayout(identity: identity, name: declaration.name, fields: fields)
            builtLayouts[identity] = layout
            return layout
        }

        for candidate in candidates {
            _ = build(candidate.identity)
        }
        return builtLayouts
    }

    private static func constructIdentity(
        for declaration: ConstructDeclaration,
        ordinal: Int?
    ) -> String {
        if let ordinal {
            return "construct:\(declaration.name)#\(ordinal)"
        }
        return "construct:\(declaration.name)"
    }

    private static func constructFieldType(
        named typeName: String,
        identitiesByName: [String: [String]],
        build: (String) -> ConstructLayout?
    ) -> ScalarType? {
        switch TypeReference.named(typeName) {
        case .named("Int"):
            return .defaultInt
        case .named("Bool"):
            return .bool
        case .named("Float"):
            return .float
        case .named("String"):
            return .string
        default:
            if let intType = ScalarType.intType(displayName: typeName) {
                return intType
            }
            guard let identities = identitiesByName[typeName],
                identities.count == 1,
                let identity = identities.first,
                let layout = build(identity)
            else {
                return nil
            }
            return .construct(identity: layout.identity, name: layout.name)
        }
    }

    static func canLower(
        _ callable: CallableDeclaration,
        lowerableFunctionNames: Set<String> = [],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> Bool {
        let signatures = Dictionary(
            uniqueKeysWithValues: lowerableFunctionNames.map {
                ($0, ScalarSignature(parameters: [], returnType: .defaultInt))
            }
        )
        return canLower(
            callable,
            lowerableFunctionSignatures: signatures,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        )
    }

    static func canLower(
        _ callable: CallableDeclaration,
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> Bool {
        guard callable.targetType == nil,
            callable.genericParameters.isEmpty,
            let signature = scalarSignature(
                for: callable,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            ),
            let body = callable.body
        else {
            return false
        }

        var locals: [String: ScalarType] = [:]
        for (parameter, type) in zip(callable.parameters, signature.parameters) {
            locals[parameter.name] = type
        }
        return canLower(
            body,
            returnType: signature.returnType,
            locals: &locals,
            lowerableFunctionSignatures: lowerableFunctionSignatures,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        )
    }

    static func rejectionReason(
        for callable: CallableDeclaration,
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> String? {
        if canLower(
            callable,
            lowerableFunctionSignatures: lowerableFunctionSignatures,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        ) {
            return nil
        }
        if callable.targetType != nil {
            return "has a target type"
        }
        if !callable.genericParameters.isEmpty {
            return "has generic parameters"
        }
        guard let returnType = callable.returnType else {
            return "has no explicit return type"
        }
        guard let scalarReturnType = scalarType(
            for: returnType,
            callable: callable,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        ) else {
            return "return type \(returnType.displayName) is not an LLVM scalar"
        }
        for parameter in callable.parameters {
            guard let typeReference = parameter.typeReference else {
                return "parameter \(parameter.name) has no explicit type"
            }
            guard scalarType(
                for: typeReference,
                callable: callable,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            ) != nil else {
                return "parameter \(parameter.name) type \(typeReference.displayName) is not an LLVM scalar"
            }
        }
        guard let body = callable.body else {
            return "has no body"
        }
        guard !body.isEmpty else {
            return "has an empty body"
        }

        var locals: [String: ScalarType] = [:]
        for (parameter, type) in zip(
            callable.parameters,
            scalarSignature(
                for: callable,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            )?.parameters ?? []
        ) {
            locals[parameter.name] = type
        }
        return statementRejectionReason(
            body,
            returnType: scalarReturnType,
            locals: &locals,
            lowerableFunctionSignatures: lowerableFunctionSignatures,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        ) ?? "uses unsupported LLVM shape"
    }

    static func scalarSignature(
        for callable: CallableDeclaration,
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> ScalarSignature? {
        guard let returnType = callable.returnType.flatMap({
            scalarType(
                for: $0,
                callable: callable,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            )
        }) else {
            return nil
        }
        let parameters = callable.parameters.compactMap {
            $0.typeReference.flatMap {
                scalarType(
                    for: $0,
                    callable: callable,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                )
            }
        }
        guard parameters.count == callable.parameters.count else {
            return nil
        }
        return ScalarSignature(parameters: parameters, returnType: returnType)
    }

    private static func scalarType(
        for typeReference: TypeReference,
        callable: CallableDeclaration,
        constructLayouts: [String: ConstructLayout],
        scalarTypes: [String: ScalarType]
    ) -> ScalarType? {
        if case .named("Self") = typeReference, let receiverType = callable.receiverType {
            return ScalarType(
                typeReference: receiverType,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            )
        }
        return ScalarType(
            typeReference: typeReference,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        )
    }

    private static func canLower(
        _ statements: [Statement],
        returnType: ScalarType,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> Bool {
        guard !statements.isEmpty else {
            return false
        }

        var sawReturn = false
        for statement in statements {
            if sawReturn {
                return false
            }

            switch statement {
            case .emitted(let text):
                guard let recordReturn = canLowerStringyRecords(
                    StringyStatementRecord.records(in: text),
                    returnType: returnType,
                    locals: &locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ) else {
                    continue
                }
                sawReturn = recordReturn
            case .macroApplication:
                continue
            case .localBinding(let declaration):
                guard canLowerLocalBinding(
                    declaration,
                    locals: &locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ) else {
                    return false
                }
            case .assignment(let target, let expression):
                guard canLowerAssignment(
                    target: target,
                    expression: expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) == .bool else {
                    return false
                }
                var bodyLocals = locals
                guard canLowerLoopBody(
                    body,
                    locals: &bodyLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) else {
                    return false
                }
            case .conditional(let branches):
                guard canLowerConditional(
                    branches,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) else {
                    return false
                }
                if conditionalAlwaysReturns(
                    branches,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) {
                    sawReturn = true
                }
            case .expression(let expression):
                guard canLowerSideEffectExpression(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) else {
                    return false
                }
            case .return(let expression?):
                guard canConvert(
                    canLower(
                        expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures,
                        constructLayouts: constructLayouts
                    ),
                    to: returnType
                ) else {
                    return false
                }
                sawReturn = true
            case .return(nil), .macroInvocation:
                return false
            }
        }

        return sawReturn
    }

    private static func canLowerStringyRecords(
        _ records: [StringyStatementRecord],
        returnType: ScalarType,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout],
        scalarTypes: [String: ScalarType]
    ) -> Bool? {
        guard !records.isEmpty else {
            return nil
        }

        var sawReturn = false
        for record in records {
            if sawReturn {
                return nil
            }

            switch record {
            case .returnStatement(let value?, let llvm):
                if concreteReturnLLVM(llvm, matches: returnType) {
                    sawReturn = true
                    continue
                }
                guard canConvert(
                    canLower(
                        value,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures,
                        constructLayouts: constructLayouts
                    ),
                    to: returnType
                ) else {
                    return nil
                }
                sawReturn = true
            case .returnStatement(nil, let llvm):
                guard concreteReturnLLVM(llvm, matches: returnType) else {
                    return nil
                }
                sawReturn = true
            case .member(_, let name, let typeName, let value):
                let type = ScalarType(
                    typeReference: .named(typeName),
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                )
                guard let type,
                    canConvert(
                        canLower(
                            value,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures,
                            constructLayouts: constructLayouts
                        ),
                        to: type
                    )
                else {
                    return nil
                }
                locals[name] = type
            case .assignment(let target, let value):
                guard let type = locals[target],
                    canConvert(
                        canLower(
                            value,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures,
                            constructLayouts: constructLayouts
                        ),
                        to: type
                    )
                else {
                    return nil
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) == .bool else {
                    return nil
                }
                var bodyLocals = locals
                guard canLowerStringyLoopBody(
                    body,
                    locals: &bodyLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ) else {
                    return nil
                }
            case .conditional(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) == .bool else {
                    return nil
                }
                var branchLocals = locals
                _ = canLowerStringyRecords(
                    body,
                    returnType: returnType,
                    locals: &branchLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                )
            case .breakStatement, .continueStatement:
                return nil
            }
        }

        return sawReturn
    }

    private static func canLowerStringyLoopBody(
        _ records: [StringyStatementRecord],
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout],
        scalarTypes: [String: ScalarType]
    ) -> Bool {
        for record in records {
            switch record {
            case .returnStatement:
                return false
            case .member(_, let name, let typeName, let value):
                guard let type = ScalarType(
                    typeReference: .named(typeName),
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ),
                    canConvert(
                        canLower(
                            value,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures,
                            constructLayouts: constructLayouts
                        ),
                        to: type
                    )
                else {
                    return false
                }
                locals[name] = type
            case .assignment(let target, let value):
                guard let type = locals[target],
                    canConvert(
                        canLower(
                            value,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures,
                            constructLayouts: constructLayouts
                        ),
                        to: type
                    )
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) == .bool else {
                    return false
                }
                var bodyLocals = locals
                guard canLowerStringyLoopBody(
                    body,
                    locals: &bodyLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ) else {
                    return false
                }
            case .conditional(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ) == .bool else {
                    return false
                }
                var branchLocals = locals
                _ = canLowerStringyLoopBody(
                    body,
                    locals: &branchLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                )
            case .breakStatement, .continueStatement:
                continue
            }
        }
        return true
    }

    private static func concreteReturnLLVM(_ llvm: String, matches returnType: ScalarType) -> Bool {
        if llvm == "ret void" {
            return false
        }
        return llvm.hasPrefix("ret \(llvmTypeName(returnType)) ")
    }

    private static func llvmTypeName(_ type: ScalarType) -> String {
        switch type {
        case .int(let bits, _):
            return "i\(bits)"
        case .bool:
            return "i1"
        case .float:
            return "double"
        case .string:
            return "%RangeString"
        case .array:
            return "%RangeArray"
        case .construct(let identity, let name):
            return "%\(sanitizeLLVMTypeName(identity.isEmpty ? name : identity))"
        }
    }

    private static func sanitizeLLVMTypeName(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "_" ? String(character) : "_"
        }.joined()
    }

    private static func statementRejectionReason(
        _ statements: [Statement],
        returnType: ScalarType,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> String? {
        var sawReturn = false
        for statement in statements {
            if sawReturn {
                return "has statements after return"
            }
            switch statement {
            case .emitted, .macroApplication:
                continue
            case .localBinding(let declaration):
                guard let type = ScalarType(typeReference: declaration.type) else {
                    return "local \(declaration.name) type \(declaration.type.displayName) is not an LLVM scalar"
                }
                guard let expressionType = canLower(
                    declaration.expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return expressionRejectionReason(
                        declaration.expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    )
                }
                guard canConvert(expressionType, to: type) else {
                    return "local \(declaration.name) initializer is \(expressionType), expected \(type)"
                }
                locals[declaration.name] = type
            case .assignment(let target, let expression):
                guard case .local(let name) = target else {
                    return "assignment target is not local state"
                }
                guard let type = locals[name] else {
                    return "assignment target \(name) is unknown"
                }
                guard let expressionType = canLower(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return expressionRejectionReason(
                        expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    )
                }
                guard canConvert(expressionType, to: type) else {
                    return "assignment to \(name) is \(expressionType), expected \(type)"
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) == .bool else {
                    return "while condition is not Bool"
                }
                var bodyLocals = locals
                if let reason = loopBodyRejectionReason(
                    body,
                    locals: &bodyLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) {
                    return reason
                }
            case .conditional(let branches):
                if !canLowerConditional(
                    branches,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) {
                    return "conditional contains unsupported LLVM statements"
                }
            case .return(let expression?):
                guard let expressionType = canLower(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return expressionRejectionReason(
                        expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    )
                }
                guard canConvert(expressionType, to: returnType) else {
                    return "return expression is \(expressionType), expected \(returnType)"
                }
                sawReturn = true
            case .return(nil), .macroInvocation:
                return "uses an unsupported statement"
            case .expression(let expression):
                guard canLowerSideEffectExpression(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return "uses an unsupported expression statement"
                }
            }
        }
        return sawReturn ? nil : "does not end with an explicit return"
    }

    private static func loopBodyRejectionReason(
        _ statements: [Statement],
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> String? {
        if canLowerLoopBody(
            statements,
            locals: &locals,
            lowerableFunctionSignatures: lowerableFunctionSignatures
        ) {
            return nil
        }
        return "loop body contains unsupported LLVM statements"
    }

    private static func expressionRejectionReason(
        _ expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> String {
        switch expression {
        case .integer, .double, .boolean:
            return "literal expression should be lowerable"
        case .identifier(let name):
            return "identifier \(name) is not an LLVM scalar local"
        case .call(let name, let arguments):
            guard let signature = lowerableFunctionSignatures[name] else {
                return "call \(name) is not LLVM-lowered"
            }
            guard arguments.count == signature.parameters.count else {
                return "call \(name) has wrong argument count"
            }
            for (argument, parameterType) in zip(arguments, signature.parameters) {
                guard let argumentType = canLower(
                    argument.value,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return expressionRejectionReason(
                        argument.value,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    )
                }
                guard canConvert(argumentType, to: parameterType) else {
                    return "call \(name) argument is \(argumentType), expected \(parameterType)"
                }
            }
            return "call \(name) should be lowerable"
        case .unary(.not, let nested):
            guard canLower(
                nested,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) == .bool else {
                return "! operand is not Bool"
            }
            return "! expression should be lowerable"
        case .binary(let lhs, let operatorSymbol, let rhs):
            guard let lhsType = canLower(
                lhs,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) else {
                return expressionRejectionReason(
                    lhs,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            }
            guard let rhsType = canLower(
                rhs,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) else {
                return expressionRejectionReason(
                    rhs,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            }
            guard resultType(for: operatorSymbol, lhs: lhsType, rhs: rhsType) != nil else {
                return "operator \(operatorSymbol.rawValue) is unsupported for \(lhsType) and \(rhsType)"
            }
            return "binary expression should be lowerable"
        case .ternary(let condition, let trueExpression, let falseExpression):
            guard canLower(
                condition,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) == .bool else {
                return "ternary condition is not Bool"
            }
            guard let trueType = canLower(
                trueExpression,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) else {
                return expressionRejectionReason(
                    trueExpression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            }
            guard let falseType = canLower(
                falseExpression,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) else {
                return expressionRejectionReason(
                    falseExpression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            }
            guard ternaryResultType(trueType, falseType) != nil else {
                return "ternary branches \(trueType) and \(falseType) are incompatible"
            }
            return "ternary expression should be lowerable"
        case .string:
            return "literal expression should be lowerable"
        case .nilLiteral:
            return "uses nil"
        case .macroInvocation:
            return "uses expression macro invocation"
        case .block:
            return "uses block expression"
        case .bindingReference:
            return "uses binding reference"
        case .array:
            return "uses Array"
        case .dictionary:
            return "uses Dictionary"
        }
    }

    private static func canLowerLoopBody(
        _ statements: [Statement],
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> Bool {
        for statement in statements {
            switch statement {
            case .emitted, .macroApplication:
                continue
            case .localBinding(let declaration):
                guard canLowerLocalBinding(
                    declaration,
                    locals: &locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .assignment(let target, let expression):
                guard canLowerAssignment(
                    target: target,
                    expression: expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) == .bool else {
                    return false
                }
                var nestedLocals = locals
                guard canLowerLoopBody(
                    body,
                    locals: &nestedLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .conditional(let branches):
                guard canLowerConditional(
                    branches,
                    returnType: .defaultInt,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .expression(let expression):
                guard canLowerSideEffectExpression(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .macroInvocation, .return:
                return false
            }
        }

        return true
    }

    private static func canLowerLocalBinding(
        _ declaration: LocalBindingDeclaration,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> Bool {
        guard let type = ScalarType(
            typeReference: declaration.type,
            constructLayouts: constructLayouts,
            scalarTypes: scalarTypes
        ),
            canConvert(
                canLower(
                    declaration.expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ),
                to: type
            )
        else {
            return false
        }
        locals[declaration.name] = type
        return true
    }

    private static func canLowerAssignment(
        target: AssignmentTarget,
        expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> Bool {
        guard case .local(let name) = target,
            let type = locals[name],
            canConvert(
                canLower(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ),
                to: type
            )
        else {
            return false
        }
        return true
    }

    private static func canLowerConditional(
        _ branches: [StatementConditionalBranch],
        returnType: ScalarType,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> Bool {
        guard !branches.isEmpty else {
            return false
        }

        for branch in branches {
            if let condition = branch.condition,
                canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) != .bool
            {
                return false
            }

            var branchLocals = locals
            guard canLower(
                branch.body,
                returnType: returnType,
                locals: &branchLocals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            )
                || canLowerLoopBody(
                    branch.body,
                    locals: &branchLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            else {
                return false
            }
        }

        return true
    }

    private static func conditionalAlwaysReturns(
        _ branches: [StatementConditionalBranch],
        returnType: ScalarType,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> Bool {
        guard branches.contains(where: { $0.condition == nil }) else {
            return false
        }

        return branches.allSatisfy { branch in
            var branchLocals = locals
            return canLower(
                branch.body,
                returnType: returnType,
                locals: &branchLocals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts
            )
        }
    }

    private static func canLower(
        _ expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> ScalarType? {
        switch expression {
        case .integer:
            return .defaultInt
        case .double:
            return .float
        case .string:
            return .string
        case .boolean:
            return .bool
        case .identifier(let name):
            if let member = lowerableMemberAccess(
                name: name,
                locals: locals,
                constructLayouts: constructLayouts
            ) {
                return member.result
            }
            return locals[name]
        case .call(let name, let arguments):
            if let arrayType = lowerableArrayAllocation(
                name: name,
                arguments: arguments,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            ) {
                return arrayType
            }
            if let scalar = lowerableScalarConstructor(
                name: name,
                arguments: arguments,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            ) {
                return scalar
            }
            if let construct = lowerableConstructInitializer(
                name: name,
                arguments: arguments,
                locals: locals,
                constructLayouts: constructLayouts,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) {
                return construct
            }
            if let memberCall = lowerableMemberCall(
                name: name,
                arguments: arguments,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) {
                guard memberCall.member != .update else {
                    return nil
                }
                return memberCall.result
            }
            guard let signature = lowerableFunctionSignatures[name],
                arguments.count == signature.parameters.count,
                zip(arguments, signature.parameters).allSatisfy({
                    argument, parameterType in
                    canConvert(
                        canLower(
                            argument.value,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures,
                            constructLayouts: constructLayouts
                        ),
                        to: parameterType
                    )
                })
            else {
                return nil
            }
            return signature.returnType
        case .unary(.not, let expression):
            guard canLower(
                expression,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts
            ) == .bool else {
                return nil
            }
            return .bool
        case .binary(let lhs, let operatorSymbol, let rhs):
            guard let lhsType = canLower(
                lhs,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts
            ),
                let rhsType = canLower(
                    rhs,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                )
            else {
                return nil
            }
            return resultType(for: operatorSymbol, lhs: lhsType, rhs: rhsType)
        case .ternary(let condition, let trueExpression, let falseExpression):
            guard canLower(
                condition,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts
            ) == .bool,
                let trueType = canLower(
                    trueExpression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                ),
                let falseType = canLower(
                    falseExpression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts
                )
            else {
                return nil
            }
            return ternaryResultType(trueType, falseType)
        case .nilLiteral, .macroInvocation, .block,
            .bindingReference, .array, .dictionary:
            return nil
        }
    }

    private static func canConvert(_ actual: ScalarType?, to expected: ScalarType) -> Bool {
        guard let actual else {
            return false
        }
        if actual == expected {
            return true
        }
        if actual.isInteger, expected.isInteger {
            return true
        }
        return actual.isInteger && expected == .float
    }

    private static func lowerableArrayAllocation(
        name: String,
        arguments: [CallArgument],
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:],
        scalarTypes: [String: ScalarType] = [:]
    ) -> ScalarType? {
        guard let elementName = arrayElementName(from: name),
            let elementType = ScalarType(
                typeReference: .named(elementName),
                constructLayouts: constructLayouts,
                scalarTypes: scalarTypes
            )
        else {
            return nil
        }
        if arguments.isEmpty {
            return .array(element: elementType)
        }
        guard arguments.count == 1 else {
            return nil
        }
        guard arguments[0].label == "capacity" || arguments[0].label == nil else {
            return nil
        }
        guard canConvert(
            canLower(
                arguments[0].value,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures,
                constructLayouts: constructLayouts
            ),
            to: .defaultInt
        ) else {
            return nil
        }
        return .array(element: elementType)
    }

    private static func arrayElementName(from callName: String) -> String? {
        guard callName.hasPrefix("Array<"), callName.hasSuffix(">") else {
            return nil
        }
        let start = callName.index(callName.startIndex, offsetBy: "Array<".count)
        let end = callName.index(before: callName.endIndex)
        return String(callName[start..<end])
    }

    private static func lowerableScalarConstructor(
        name: String,
        arguments: [CallArgument],
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout],
        scalarTypes: [String: ScalarType]
    ) -> ScalarType? {
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
        guard let target,
            canConvert(
                canLower(
                    arguments[0].value,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures,
                    constructLayouts: constructLayouts,
                    scalarTypes: scalarTypes
                ),
                to: target
            )
        else {
            return nil
        }
        return target
    }

    private static func lowerableConstructInitializer(
        name: String,
        arguments: [CallArgument],
        locals: [String: ScalarType],
        constructLayouts: [String: ConstructLayout],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> ScalarType? {
        guard let layout = uniqueConstructLayout(named: name, in: constructLayouts),
            arguments.count == layout.fields.count
        else {
            return nil
        }

        for field in layout.fields {
            guard let argument = arguments.first(where: { $0.label == field.name }),
                canConvert(
                    canLower(
                        argument.value,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures,
                        constructLayouts: constructLayouts
                    ),
                    to: field.type
                )
            else {
                return nil
            }
        }
        return .construct(identity: layout.identity, name: layout.name)
    }

    private static func canLowerSideEffectExpression(
        _ expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> Bool {
        guard case .call(let name, let arguments) = expression,
            let memberCall = lowerableMemberCall(
                name: name,
                arguments: arguments,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            )
        else {
            return false
        }
        return memberCall.member == .append || memberCall.member == .update
    }

    private struct LowerableMemberAccess {
        let baseName: String
        let baseType: ScalarType
        let member: LowerableMember
        let result: ScalarType
    }

    private enum LowerableMember: Equatable {
        case count
        case byteCount
        case element
        case isEmpty
        case append
        case update
        case field(index: Int)
    }

    private static func lowerableMemberAccess(
        name: String,
        locals: [String: ScalarType],
        constructLayouts: [String: ConstructLayout] = [:]
    ) -> LowerableMemberAccess? {
        guard let dotIndex = name.lastIndex(of: ".") else {
            return nil
        }
        let baseName = String(name[..<dotIndex])
        let memberName = String(name[name.index(after: dotIndex)...])
        guard let baseType = lowerableIdentifierType(
            name: baseName,
            locals: locals,
            constructLayouts: constructLayouts
        ) else {
            return nil
        }

        if case .construct(let constructIdentity, _) = baseType,
            let layout = constructLayouts[constructIdentity],
            let field = layout.field(named: memberName)
        {
            return LowerableMemberAccess(
                baseName: baseName,
                baseType: baseType,
                member: .field(index: field.index),
                result: field.field.type
            )
        }

        guard let member = lowerableMember(baseType: baseType, name: memberName) else {
            return nil
        }

        return LowerableMemberAccess(
            baseName: baseName,
            baseType: baseType,
            member: member,
            result: resultType(for: member, baseType: baseType)
        )
    }

    private static func lowerableIdentifierType(
        name: String,
        locals: [String: ScalarType],
        constructLayouts: [String: ConstructLayout]
    ) -> ScalarType? {
        if let local = locals[name] {
            return local
        }
        return lowerableMemberAccess(
            name: name,
            locals: locals,
            constructLayouts: constructLayouts
        )?.result
    }

    private static func uniqueConstructLayout(
        named name: String,
        in constructLayouts: [String: ConstructLayout]
    ) -> ConstructLayout? {
        let matches = constructLayouts.values.filter { $0.name == name }
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private static func lowerableMember(
        baseType: ScalarType,
        name: String
    ) -> LowerableMember? {
        switch (baseType, name) {
        case (.string, "byteCount"):
            return .byteCount
        case (.string, "isEmpty"):
            return .isEmpty
        case (.array, "count"):
            return .count
        case (.array, "isEmpty"):
            return .isEmpty
        default:
            return nil
        }
    }

    private static func resultType(for member: LowerableMember, baseType: ScalarType) -> ScalarType {
        switch member {
        case .count:
            return .defaultInt
        case .byteCount:
            return .defaultInt
        case .element:
            if case .array(let elementType) = baseType {
                return elementType
            }
            return .defaultInt
        case .isEmpty:
            return .bool
        case .append:
            return baseType
        case .update:
            return baseType
        case .field:
            return .defaultInt
        }
    }

    private struct LowerableMemberCall {
        let baseName: String
        let baseType: ScalarType
        let member: LowerableMember
        let result: ScalarType
    }

    private static func lowerableMemberCall(
        name: String,
        arguments: [CallArgument],
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> LowerableMemberCall? {
        guard let dotIndex = name.lastIndex(of: ".") else {
            return nil
        }
        let baseName = String(name[..<dotIndex])
        let memberName = String(name[name.index(after: dotIndex)...])
        guard let baseType = locals[baseName],
            let member = lowerableMemberCall(baseType: baseType, name: memberName)
        else {
            return nil
        }

        switch member {
        case .append:
            guard case .array(let elementType) = baseType else {
                return nil
            }
            guard arguments.count == 1,
                canConvert(
                    argumentValue(labeled: "element", at: 0, in: arguments).flatMap {
                        canLower(
                            $0,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures
                        )
                    },
                    to: elementType
                )
            else {
                return nil
            }
        case .element:
            guard arguments.count == 1,
                canConvert(
                    canLower(
                        arguments[0].value,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    ),
                    to: .defaultInt
                )
            else {
                return nil
            }
        case .update:
            guard case .array(let elementType) = baseType else {
                return nil
            }
            guard arguments.count == 2,
                canConvert(
                    argumentValue(labeled: "element", at: 0, in: arguments).flatMap {
                        canLower(
                            $0,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures
                        )
                    },
                    to: elementType
                ),
                canConvert(
                    argumentValue(labeled: "index", at: 1, in: arguments).flatMap {
                        canLower(
                            $0,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures
                        )
                    },
                    to: .defaultInt
                )
            else {
                return nil
            }
        default:
            return nil
        }

        return LowerableMemberCall(
            baseName: baseName,
            baseType: baseType,
            member: member,
            result: resultType(for: member, baseType: baseType)
        )
    }

    private static func lowerableMemberCall(
        baseType: ScalarType,
        name: String
    ) -> LowerableMember? {
        switch (baseType, name) {
        case (.array, "append"):
            return .append
        case (.array, "element"):
            return .element
        case (.array, "update"):
            return .update
        default:
            return nil
        }
    }

    private static func argumentValue(
        labeled label: String,
        at fallbackIndex: Int,
        in arguments: [CallArgument]
    ) -> Expression? {
        if let labeledArgument = arguments.first(where: { $0.label == label }) {
            return labeledArgument.value
        }
        guard arguments.indices.contains(fallbackIndex) else {
            return nil
        }
        return arguments[fallbackIndex].value
    }

    private static func ternaryResultType(_ lhs: ScalarType, _ rhs: ScalarType) -> ScalarType? {
        if lhs == rhs, lhs != .string {
            return lhs
        }
        if lhs.isNumeric, rhs.isNumeric {
            if lhs == .float || rhs == .float {
                return .float
            }
            return commonIntegerType(lhs, rhs)
        }
        return nil
    }

    private static func resultType(
        for operatorSymbol: BinaryOperator,
        lhs: ScalarType,
        rhs: ScalarType
    ) -> ScalarType? {
        switch operatorSymbol {
        case .addition, .subtraction, .multiplication, .division:
            guard lhs.isNumeric, rhs.isNumeric else {
                return nil
            }
            if lhs == .float || rhs == .float {
                return .float
            }
            return commonIntegerType(lhs, rhs)
        case .remainder:
            return commonIntegerType(lhs, rhs)
        case .equal, .notEqual:
            if lhs == rhs, lhs != .string {
                return .bool
            }
            return lhs.isNumeric && rhs.isNumeric ? .bool : nil
        case .less, .lessEqual, .greater, .greaterEqual:
            return lhs.isNumeric && rhs.isNumeric ? .bool : nil
        case .and, .or:
            return lhs == .bool && rhs == .bool ? .bool : nil
        case .nilCoalescing:
            return nil
        case .rangeUntil, .closedRange:
            return nil
        }
    }
}

private extension LLVMLowerability.ScalarType {
    var isNumeric: Bool {
        switch self {
        case .int(_, _), .float:
            return true
        case .bool, .string, .array:
            return false
        case .construct:
            return false
        }
    }

    var isInteger: Bool {
        if case .int(_, _) = self {
            return true
        }
        return false
    }

    var integerWidth: Int? {
        guard case .int(let bits, _) = self else {
            return nil
        }
        return bits
    }

    var isSignedInteger: Bool? {
        guard case .int(_, let signed) = self else {
            return nil
        }
        return signed
    }
}

private func commonIntegerType(
    _ lhs: LLVMLowerability.ScalarType,
    _ rhs: LLVMLowerability.ScalarType
) -> LLVMLowerability.ScalarType? {
    guard case .int(let lhsBits, let lhsSigned) = lhs,
        case .int(let rhsBits, let rhsSigned) = rhs
    else {
        return nil
    }
    if lhsBits == rhsBits {
        return .int(bits: lhsBits, signed: lhsSigned && rhsSigned)
    }
    if lhsBits > rhsBits {
        return lhs
    }
    return rhs
}
