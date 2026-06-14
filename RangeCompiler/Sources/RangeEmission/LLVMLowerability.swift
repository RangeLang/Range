import RangeCompiler

enum LLVMLowerability {
    static func canLower(
        _ callable: CallableDeclaration,
        lowerableFunctionNames: Set<String> = []
    ) -> Bool {
        guard callable.targetType == nil,
            callable.receiverType == nil,
            callable.genericParameters.isEmpty,
            callable.returnType?.displayName == "Int",
            callable.parameters.allSatisfy({ $0.typeReference?.displayName == "Int" }),
            let body = callable.body
        else {
            return false
        }

        var locals = Dictionary(
            uniqueKeysWithValues: callable.parameters.map { ($0.name, ScalarType.int) }
        )
        return canLower(body, locals: &locals, lowerableFunctionNames: lowerableFunctionNames)
    }

    private enum ScalarType {
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

    private static func canLower(
        _ statements: [Statement],
        locals: inout [String: ScalarType],
        lowerableFunctionNames: Set<String>
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
                        lowerableFunctionNames: lowerableFunctionNames
                    ) == type
                else {
                    return false
                }
                locals[declaration.name] = type
            case .assignment(let target, let expression):
                guard case .local(let name) = target,
                    let type = locals[name],
                    canLower(expression, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                        == type
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(condition, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                    == .bool
                else {
                    return false
                }
                var bodyLocals = locals
                guard canLowerLoopBody(
                    body,
                    locals: &bodyLocals,
                    lowerableFunctionNames: lowerableFunctionNames
                ) else {
                    return false
                }
            case .conditional(let branches):
                guard canLowerConditional(
                    branches,
                    locals: locals,
                    lowerableFunctionNames: lowerableFunctionNames
                ) else {
                    return false
                }
                if conditionalAlwaysReturns(
                    branches,
                    locals: locals,
                    lowerableFunctionNames: lowerableFunctionNames
                ) {
                    sawReturn = true
                }
            case .return(let expression?):
                guard canLower(expression, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                    == .int
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
        lowerableFunctionNames: Set<String>
    ) -> Bool {
        for statement in statements {
            switch statement {
            case .localBinding(let declaration):
                guard let type = ScalarType(typeReference: declaration.type),
                    canLower(
                        declaration.expression,
                        locals: locals,
                        lowerableFunctionNames: lowerableFunctionNames
                    ) == type
                else {
                    return false
                }
                locals[declaration.name] = type
            case .assignment(let target, let expression):
                guard case .local(let name) = target,
                    let type = locals[name],
                    canLower(expression, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                        == type
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLower(condition, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                    == .bool
                else {
                    return false
                }
                var nestedLocals = locals
                guard canLowerLoopBody(
                    body,
                    locals: &nestedLocals,
                    lowerableFunctionNames: lowerableFunctionNames
                ) else {
                    return false
                }
            case .conditional(let branches):
                guard canLowerConditional(
                    branches,
                    locals: locals,
                    lowerableFunctionNames: lowerableFunctionNames
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
        locals: [String: ScalarType],
        lowerableFunctionNames: Set<String>
    ) -> Bool {
        guard !branches.isEmpty else {
            return false
        }

        for branch in branches {
            if let condition = branch.condition,
                canLower(condition, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                    != .bool
            {
                return false
            }

            var branchLocals = locals
            guard canLower(
                branch.body,
                locals: &branchLocals,
                lowerableFunctionNames: lowerableFunctionNames
            )
                || canLowerLoopBody(
                    branch.body,
                    locals: &branchLocals,
                    lowerableFunctionNames: lowerableFunctionNames
                )
            else {
                return false
            }
        }

        return true
    }

    private static func conditionalAlwaysReturns(
        _ branches: [StatementConditionalBranch],
        locals: [String: ScalarType],
        lowerableFunctionNames: Set<String>
    ) -> Bool {
        guard branches.contains(where: { $0.condition == nil }) else {
            return false
        }

        return branches.allSatisfy { branch in
            var branchLocals = locals
            return canLower(
                branch.body,
                locals: &branchLocals,
                lowerableFunctionNames: lowerableFunctionNames
            )
        }
    }

    private static func canLower(
        _ expression: Expression,
        locals: [String: ScalarType],
        lowerableFunctionNames: Set<String>
    ) -> ScalarType? {
        switch expression {
        case .integer:
            return .int
        case .boolean:
            return .bool
        case .identifier(let name):
            return locals[name]
        case .call(let name, let arguments):
            guard lowerableFunctionNames.contains(name),
                arguments.allSatisfy({
                    canLower(
                        $0.value,
                        locals: locals,
                        lowerableFunctionNames: lowerableFunctionNames
                    ) == .int
                })
            else {
                return nil
            }
            return .int
        case .unary(.not, let expression):
            guard canLower(
                expression,
                locals: locals,
                lowerableFunctionNames: lowerableFunctionNames
            ) == .bool else {
                return nil
            }
            return .bool
        case .binary(let lhs, let operatorSymbol, let rhs):
            guard let operandType = operandType(for: operatorSymbol),
                canLower(lhs, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
                    == operandType,
                canLower(rhs, locals: locals, lowerableFunctionNames: lowerableFunctionNames)
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
