import RangeCompiler

enum LLVMLowerability {
    struct ScalarSignature {
        var parameters: [ScalarType]
        var returnType: ScalarType
    }

    enum ScalarType {
        case int
        case bool
        case float

        init?(typeReference: TypeReference) {
            switch typeReference.displayName {
            case "Int":
                self = .int
            case "Bool":
                self = .bool
            case "Float":
                self = .float
            default:
                return nil
            }
        }
    }

    static func canLower(
        _ callable: CallableDeclaration,
        lowerableFunctionNames: Set<String> = []
    ) -> Bool {
        let signatures = Dictionary(
            uniqueKeysWithValues: lowerableFunctionNames.map {
                ($0, ScalarSignature(parameters: [], returnType: .int))
            }
        )
        return canLower(callable, lowerableFunctionSignatures: signatures)
    }

    static func canLower(
        _ callable: CallableDeclaration,
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        guard callable.targetType == nil,
            callable.receiverType == nil,
            callable.genericParameters.isEmpty,
            let signature = scalarSignature(for: callable),
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
            lowerableFunctionSignatures: lowerableFunctionSignatures
        )
    }

    static func rejectionReason(
        for callable: CallableDeclaration,
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> String? {
        if canLower(callable, lowerableFunctionSignatures: lowerableFunctionSignatures) {
            return nil
        }
        if callable.targetType != nil {
            return "has a target type"
        }
        if callable.receiverType != nil {
            return "has a receiver type"
        }
        if !callable.genericParameters.isEmpty {
            return "has generic parameters"
        }
        guard let returnType = callable.returnType else {
            return "has no explicit return type"
        }
        guard let scalarReturnType = ScalarType(typeReference: returnType) else {
            return "return type \(returnType.displayName) is not an LLVM scalar"
        }
        for parameter in callable.parameters {
            guard let typeReference = parameter.typeReference else {
                return "parameter \(parameter.name) has no explicit type"
            }
            guard ScalarType(typeReference: typeReference) != nil else {
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
        for (parameter, type) in zip(callable.parameters, scalarSignature(for: callable)?.parameters ?? []) {
            locals[parameter.name] = type
        }
        return statementRejectionReason(
            body,
            returnType: scalarReturnType,
            locals: &locals,
            lowerableFunctionSignatures: lowerableFunctionSignatures
        ) ?? "uses unsupported LLVM shape"
    }

    static func scalarSignature(for callable: CallableDeclaration) -> ScalarSignature? {
        guard let returnType = callable.returnType.flatMap(ScalarType.init(typeReference:)) else {
            return nil
        }
        let parameters = callable.parameters.compactMap {
            $0.typeReference.flatMap(ScalarType.init(typeReference:))
        }
        guard parameters.count == callable.parameters.count else {
            return nil
        }
        return ScalarSignature(parameters: parameters, returnType: returnType)
    }

    private static func canLower(
        _ statements: [Statement],
        returnType: ScalarType,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
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
            case .compoundAssignment(let target, let operatorSymbol, let expression):
                guard canLowerCompoundAssignment(
                    target: target,
                    operatorSymbol: operatorSymbol,
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
                var bodyLocals = locals
                guard canLowerLoopBody(
                    body,
                    locals: &bodyLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .conditional(let branches):
                guard canLowerConditional(
                    branches,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
                if conditionalAlwaysReturns(
                    branches,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) {
                    sawReturn = true
                }
            case .switchStatement(let expression, let cases, let defaultBody):
                guard canLowerSwitch(
                    expression: expression,
                    cases: cases,
                    defaultBody: defaultBody,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
                if switchAlwaysReturns(
                    cases: cases,
                    defaultBody: defaultBody,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) {
                    sawReturn = true
                }
            case .return(let expression?):
                guard canConvert(
                    canLower(
                        expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    ),
                    to: returnType
                ) else {
                    return false
                }
                sawReturn = true
            case .return(nil), .macroInvocation, .expand, .background, .deferBlock, .localCallable,
                .derived, .expression, .forEach, .break, .continue:
                return false
            }
        }

        return sawReturn
    }

    private static func statementRejectionReason(
        _ statements: [Statement],
        returnType: ScalarType,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> String? {
        var sawReturn = false
        for statement in statements {
            if sawReturn {
                return "has statements after return"
            }
            switch statement {
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
            case .compoundAssignment(let target, let operatorSymbol, let expression):
                guard case .plusEquals = operatorSymbol else {
                    return "compound assignment \(operatorSymbol.rawValue) is unsupported"
                }
                guard case .local(let name) = target else {
                    return "compound assignment target is not local state"
                }
                guard let type = locals[name] else {
                    return "compound assignment target \(name) is unknown"
                }
                guard let rhsType = canLower(
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
                guard resultType(for: .addition, lhs: type, rhs: rhsType) == type else {
                    return "compound assignment \(name) += value cannot preserve \(type)"
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
            case .switchStatement(let expression, let cases, let defaultBody):
                if let reason = switchRejectionReason(
                    expression: expression,
                    cases: cases,
                    defaultBody: defaultBody,
                    returnType: returnType,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) {
                    return reason
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
            case .return(nil):
                return "uses bare return"
            case .macroInvocation:
                return "uses a statement macro invocation"
            case .expand:
                return "uses expand"
            case .background:
                return "uses background"
            case .deferBlock:
                return "uses defer"
            case .localCallable:
                return "uses a local function"
            case .derived:
                return "uses derived"
            case .expression:
                return "uses an expression statement"
            case .forEach:
                return "uses forEach"
            case .break:
                return "uses break outside a lowerable loop body"
            case .continue:
                return "uses continue outside a lowerable loop body"
            }
        }
        return sawReturn ? nil : "does not end with an explicit return"
    }

    private static func loopBodyRejectionReason(
        _ statements: [Statement],
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
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
        lowerableFunctionSignatures: [String: ScalarSignature]
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
        case .string, .interpolatedString:
            return "uses String"
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
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        for statement in statements {
            switch statement {
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
            case .compoundAssignment(let target, let operatorSymbol, let expression):
                guard canLowerCompoundAssignment(
                    target: target,
                    operatorSymbol: operatorSymbol,
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
                    returnType: .int,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .switchStatement(let expression, let cases, let defaultBody):
                guard canLowerSwitch(
                    expression: expression,
                    cases: cases,
                    defaultBody: defaultBody,
                    returnType: .int,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ) else {
                    return false
                }
            case .macroInvocation, .expand, .background, .deferBlock, .localCallable, .derived,
                .expression, .forEach, .return:
                return false
            case .break, .continue:
                continue
            }
        }

        return true
    }

    private static func canLowerSwitch(
        expression: Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?,
        returnType: ScalarType,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        switchRejectionReason(
            expression: expression,
            cases: cases,
            defaultBody: defaultBody,
            returnType: returnType,
            locals: locals,
            lowerableFunctionSignatures: lowerableFunctionSignatures
        ) == nil
    }

    private static func switchRejectionReason(
        expression: Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?,
        returnType: ScalarType,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> String? {
        guard let subjectType = canLower(
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
        guard subjectType == .int || subjectType == .bool else {
            return "switch subject \(subjectType) is not Int or Bool"
        }
        guard !cases.isEmpty else {
            return "switch has no cases"
        }
        guard let defaultBody else {
            return "switch has no default"
        }

        var literals = Set<String>()
        for switchCase in cases {
            guard let literal = switchCaseLiteral(switchCase.pattern, subjectType: subjectType) else {
                return "switch case pattern is not a \(subjectType) literal"
            }
            guard literals.insert(literal).inserted else {
                return "switch has duplicate case \(literal)"
            }

            var returningBranchLocals = locals
            var nonReturningBranchLocals = locals
            guard canLower(
                switchCase.body,
                returnType: returnType,
                locals: &returningBranchLocals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            )
                || canLowerLoopBody(
                    switchCase.body,
                    locals: &nonReturningBranchLocals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            else {
                return "switch case contains unsupported LLVM statements"
            }
        }

        var returningDefaultLocals = locals
        var nonReturningDefaultLocals = locals
        guard canLower(
            defaultBody,
            returnType: returnType,
            locals: &returningDefaultLocals,
            lowerableFunctionSignatures: lowerableFunctionSignatures
        )
            || canLowerLoopBody(
                defaultBody,
                locals: &nonReturningDefaultLocals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            )
        else {
            return "switch default contains unsupported LLVM statements"
        }

        return nil
    }

    private static func switchAlwaysReturns(
        cases: [SwitchCase],
        defaultBody: [Statement]?,
        returnType: ScalarType,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        guard let defaultBody else {
            return false
        }

        var defaultLocals = locals
        guard canLower(
            defaultBody,
            returnType: returnType,
            locals: &defaultLocals,
            lowerableFunctionSignatures: lowerableFunctionSignatures
        ) else {
            return false
        }

        return cases.allSatisfy { switchCase in
            var branchLocals = locals
            return canLower(
                switchCase.body,
                returnType: returnType,
                locals: &branchLocals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            )
        }
    }

    private static func switchCaseLiteral(
        _ pattern: SwitchCasePattern,
        subjectType: ScalarType
    ) -> String? {
        guard case .expression(let expression) = pattern else {
            return nil
        }

        switch (subjectType, expression) {
        case (.int, .integer(let value)):
            return String(value)
        case (.bool, .boolean(let value)):
            return value ? "1" : "0"
        default:
            return nil
        }
    }

    private static func canLowerLocalBinding(
        _ declaration: LocalBindingDeclaration,
        locals: inout [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        guard let type = ScalarType(typeReference: declaration.type),
            canConvert(
                canLower(
                    declaration.expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
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
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        guard case .local(let name) = target,
            let type = locals[name],
            canConvert(
                canLower(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ),
                to: type
            )
        else {
            return false
        }
        return true
    }

    private static func canLowerCompoundAssignment(
        target: AssignmentTarget,
        operatorSymbol: CompoundOperator,
        expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> Bool {
        guard case .plusEquals = operatorSymbol,
            case .local(let name) = target,
            let type = locals[name],
            let rhsType = canLower(
                expression,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ),
            resultType(for: .addition, lhs: type, rhs: rhsType) == type
        else {
            return false
        }
        return true
    }

    private static func canLowerConditional(
        _ branches: [StatementConditionalBranch],
        returnType: ScalarType,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
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
        lowerableFunctionSignatures: [String: ScalarSignature]
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
                lowerableFunctionSignatures: lowerableFunctionSignatures
            )
        }
    }

    private static func canLower(
        _ expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionSignatures: [String: ScalarSignature]
    ) -> ScalarType? {
        switch expression {
        case .integer:
            return .int
        case .double:
            return .float
        case .boolean:
            return .bool
        case .identifier(let name):
            return locals[name]
        case .call(let name, let arguments):
            guard let signature = lowerableFunctionSignatures[name],
                arguments.count == signature.parameters.count,
                zip(arguments, signature.parameters).allSatisfy({
                    argument, parameterType in
                    canConvert(
                        canLower(
                            argument.value,
                            locals: locals,
                            lowerableFunctionSignatures: lowerableFunctionSignatures
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
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) == .bool else {
                return nil
            }
            return .bool
        case .binary(let lhs, let operatorSymbol, let rhs):
            guard let lhsType = canLower(
                lhs,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ),
                let rhsType = canLower(
                    rhs,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            else {
                return nil
            }
            return resultType(for: operatorSymbol, lhs: lhsType, rhs: rhsType)
        case .ternary(let condition, let trueExpression, let falseExpression):
            guard canLower(
                condition,
                locals: locals,
                lowerableFunctionSignatures: lowerableFunctionSignatures
            ) == .bool,
                let trueType = canLower(
                    trueExpression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                ),
                let falseType = canLower(
                    falseExpression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
            else {
                return nil
            }
            return ternaryResultType(trueType, falseType)
        case .string, .interpolatedString, .nilLiteral, .macroInvocation, .block,
            .bindingReference, .array, .dictionary:
            return nil
        }
    }

    private static func canConvert(_ actual: ScalarType?, to expected: ScalarType) -> Bool {
        guard let actual else {
            return false
        }
        return actual == expected || (actual == .int && expected == .float)
    }

    private static func ternaryResultType(_ lhs: ScalarType, _ rhs: ScalarType) -> ScalarType? {
        if lhs == rhs {
            return lhs
        }
        if lhs.isNumeric, rhs.isNumeric {
            return lhs == .float || rhs == .float ? .float : .int
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
            return lhs == .float || rhs == .float ? .float : .int
        case .remainder:
            return lhs == .int && rhs == .int ? .int : nil
        case .equal, .notEqual:
            if lhs == rhs {
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
        case .int, .float:
            return true
        case .bool:
            return false
        }
    }
}
