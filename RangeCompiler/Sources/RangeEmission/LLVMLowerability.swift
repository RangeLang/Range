import RangeCompiler

enum LLVMLowerability {
    struct ScalarSignature {
        var parameters: [ScalarType]
        var returnType: ScalarType
    }

    enum ScalarType {
        case int
        case bool

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
                guard let type = ScalarType(typeReference: declaration.type),
                    canLower(
                        declaration.expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    ) == type
                else {
                    return false
                }
                locals[declaration.name] = type
            case .assignment(let target, let expression):
                guard case .local(let name) = target,
                    let type = locals[name],
                    canLower(
                        expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    )
                        == type
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
                    == .bool
                else {
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
                guard canLower(
                    expression,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
                    == returnType
                else {
                    return false
                }
                sawReturn = true
            case .return(nil), .macroInvocation, .expand, .background, .deferBlock, .localCallable,
                .derived, .compoundAssignment, .expression, .forEach, .break, .continue,
                .switchStatement:
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
                guard let type = ScalarType(typeReference: declaration.type),
                    canLower(
                        declaration.expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    ) == type
                else {
                    return false
                }
                locals[declaration.name] = type
            case .assignment(let target, let expression):
                guard case .local(let name) = target,
                    let type = locals[name],
                    canLower(
                        expression,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    )
                        == type
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(
                    condition,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
                    == .bool
                else {
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
                .compoundAssignment, .expression, .forEach, .return, .break, .continue,
                .switchStatement:
                return false
            }
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
                )
                    != .bool
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
        case .boolean:
            return .bool
        case .identifier(let name):
            return locals[name]
        case .call(let name, let arguments):
            guard let signature = lowerableFunctionSignatures[name],
                arguments.count == signature.parameters.count,
                zip(arguments, signature.parameters).allSatisfy({
                    argument, parameterType in
                    canLower(
                        argument.value,
                        locals: locals,
                        lowerableFunctionSignatures: lowerableFunctionSignatures
                    ) == parameterType
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
            guard let operandType = operandType(for: operatorSymbol),
                canLower(
                    lhs,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
                    == operandType,
                canLower(
                    rhs,
                    locals: locals,
                    lowerableFunctionSignatures: lowerableFunctionSignatures
                )
                    == operandType
            else {
                return nil
            }
            return resultType(for: operatorSymbol)
        case .double, .string, .interpolatedString, .nilLiteral, .macroInvocation, .block,
            .bindingReference, .array, .dictionary, .ternary:
            return nil
        }
    }

    private static func operandType(for operatorSymbol: BinaryOperator) -> ScalarType? {
        switch operatorSymbol {
        case .addition, .subtraction, .multiplication, .division, .remainder:
            return .int
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            return .int
        case .and, .or:
            return .bool
        case .nilCoalescing:
            return nil
        }
    }

    private static func resultType(for operatorSymbol: BinaryOperator) -> ScalarType? {
        switch operatorSymbol {
        case .addition, .subtraction, .multiplication, .division, .remainder:
            return .int
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            return .bool
        case .and, .or:
            return .bool
        case .nilCoalescing:
            return nil
        }
    }
}
