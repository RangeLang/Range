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
                .derived, .expression, .forEach, .break, .continue, .switchStatement:
                return false
            }
        }

        return sawReturn
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
            case .macroInvocation, .expand, .background, .deferBlock, .localCallable, .derived,
                .expression, .forEach, .return, .switchStatement:
                return false
            case .break, .continue:
                continue
            }
        }

        return true
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
