import RangeSyntax

enum LLVMLowerability {
    static func canLower(_ callable: CallableDeclaration) -> Bool {
        guard callable.targetType == nil,
            callable.receiverType == nil,
            callable.genericParameters.isEmpty,
            callable.returnType?.displayName == "Int",
            callable.parameters.allSatisfy({ $0.typeReference?.displayName == "Int" }),
            let body = callable.body
        else {
            return false
        }

        var localNames = Set(callable.parameters.map(\.name))
        return canLower(body, localNames: &localNames)
    }

    private static func canLower(_ statements: [Statement], localNames: inout Set<String>) -> Bool {
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
                guard isMutable(declaration.kind),
                    declaration.type.displayName == "Int",
                    canLower(declaration.expression, localNames: localNames)
                else {
                    return false
                }
                localNames.insert(declaration.name)
            case .assignment(let target, let expression):
                guard case .local(let name) = target,
                    localNames.contains(name),
                    canLower(expression, localNames: localNames)
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLowerCondition(condition, localNames: localNames) else {
                    return false
                }
                var bodyLocalNames = localNames
                guard canLowerLoopBody(body, localNames: &bodyLocalNames) else {
                    return false
                }
            case .return(let expression?):
                guard canLower(expression, localNames: localNames) else {
                    return false
                }
                sawReturn = true
            case .return(nil), .macroInvocation, .expand, .background, .deferBlock, .localCallable,
                .derived, .compoundAssignment, .expression, .forEach, .conditional, .break,
                .continue, .switchStatement:
                return false
            }
        }

        return sawReturn
    }

    private static func canLowerLoopBody(
        _ statements: [Statement],
        localNames: inout Set<String>
    ) -> Bool {
        for statement in statements {
            switch statement {
            case .localBinding(let declaration):
                guard isMutable(declaration.kind),
                    declaration.type.displayName == "Int",
                    canLower(declaration.expression, localNames: localNames)
                else {
                    return false
                }
                localNames.insert(declaration.name)
            case .assignment(let target, let expression):
                guard case .local(let name) = target,
                    localNames.contains(name),
                    canLower(expression, localNames: localNames)
                else {
                    return false
                }
            case .whileLoop(let condition, let body):
                guard canLowerCondition(condition, localNames: localNames) else {
                    return false
                }
                var nestedLocalNames = localNames
                guard canLowerLoopBody(body, localNames: &nestedLocalNames) else {
                    return false
                }
            case .macroInvocation, .expand, .background, .deferBlock, .localCallable, .derived,
                .compoundAssignment, .expression, .forEach, .conditional, .return, .break,
                .continue, .switchStatement:
                return false
            }
        }

        return true
    }

    private static func canLower(_ expression: Expression, localNames: Set<String>) -> Bool {
        switch expression {
        case .integer:
            return true
        case .identifier(let name):
            return localNames.contains(name)
        case .binary(let lhs, let operatorSymbol, let rhs):
            return canLower(operatorSymbol)
                && canLower(lhs, localNames: localNames)
                && canLower(rhs, localNames: localNames)
        case .double, .string, .interpolatedString, .boolean, .nilLiteral, .macroInvocation,
            .block, .call, .bindingReference, .array, .dictionary, .ternary, .unary:
            return false
        }
    }

    private static func canLowerCondition(_ expression: Expression, localNames: Set<String>) -> Bool {
        guard case .binary(let lhs, let operatorSymbol, let rhs) = expression else {
            return false
        }
        return canLowerComparison(operatorSymbol)
            && canLower(lhs, localNames: localNames)
            && canLower(rhs, localNames: localNames)
    }

    private static func canLower(_ operatorSymbol: BinaryOperator) -> Bool {
        switch operatorSymbol {
        case .addition, .subtraction, .multiplication, .division, .remainder:
            return true
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual,
            .and, .or, .nilCoalescing:
            return false
        }
    }

    private static func canLowerComparison(_ operatorSymbol: BinaryOperator) -> Bool {
        switch operatorSymbol {
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            return true
        case .addition, .subtraction, .multiplication, .division, .remainder,
            .and, .or, .nilCoalescing:
            return false
        }
    }

    private static func isMutable(_ kind: LocalBindingKind) -> Bool {
        guard case .mutable = kind else {
            return false
        }
        return true
    }
}
