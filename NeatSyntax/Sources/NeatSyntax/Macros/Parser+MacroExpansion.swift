import Foundation

extension Parser {
    mutating func parseFreestandingBlockMacroExpansionIfPresent(
        localBindings: inout [String: LocalBindingKind]
    ) throws -> [Statement]? {
        guard case .hashDirective(let name) = peek(),
            let macro = currentMacroDeclarations[name]
        else {
            return nil
        }

        guard case .freestanding(let targetType) = macro.target, targetType.displayName == "Block"
        else {
            return nil
        }

        advance()

        if try parseMacroArgumentClauseIfPresent() != nil {
            throw ParseError(
                "Freestanding block macro #\(name) does not support argument clauses yet.")
        }

        let targetBlock = try parseStatementBlock(baseLocalBindings: localBindings)
        return try expandFreestandingBlockMacro(macro, targetBlock: targetBlock)
    }

    func expandFreestandingBlockMacro(
        _ macro: MacroDeclaration,
        targetBlock: [Statement]
    ) throws -> [Statement] {
        let rewriteBody = try rewriteBody(for: macro)
        return substituteMacroTargetCalls(
            in: rewriteBody,
            targetBinding: macro.bindings.target,
            targetBlock: targetBlock
        )
    }

    func rewriteBody(for macro: MacroDeclaration) throws -> [Statement] {
        var rewriteCalls: [[Statement]] = []

        for statement in macro.body {
            guard case .expression(let expression) = statement else {
                continue
            }
            guard case .call(let name, let arguments) = expression else {
                continue
            }
            guard name == "\(macro.bindings.result).rewrite" else {
                continue
            }
            guard arguments.count == 1 else {
                continue
            }
            guard case .block(let body) = arguments[0].value else {
                throw ParseError(
                    "Macro #\(macro.name) result.rewrite(...) must receive a block expression for Freestanding<Block>."
                )
            }
            rewriteCalls.append(body)
        }

        guard let rewriteBody = rewriteCalls.first else {
            throw ParseError(
                "Macro #\(macro.name) must call \(macro.bindings.result).rewrite(...) with a block expression."
            )
        }

        if rewriteCalls.count > 1 {
            throw ParseError("Macro #\(macro.name) can only rewrite once in this bootstrap pass.")
        }

        return rewriteBody
    }

    func substituteMacroTargetCalls(
        in statements: [Statement],
        targetBinding: String,
        targetBlock: [Statement]
    ) -> [Statement] {
        statements.flatMap { statement in
            substituteMacroTargetCall(
                in: statement, targetBinding: targetBinding, targetBlock: targetBlock)
        }
    }

    func substituteMacroTargetCall(
        in statement: Statement,
        targetBinding: String,
        targetBlock: [Statement]
    ) -> [Statement] {
        switch statement {
        case .expression(.call(let name, let arguments))
        where name == targetBinding && arguments.isEmpty:
            return targetBlock
        case .derived(let name, let typeName, let body):
            return [
                .derived(
                    name: name,
                    typeName: typeName,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .forEach(let name, let sequence, let body):
            return [
                .forEach(
                    name: name,
                    sequence: sequence,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .whileLoop(let condition, let body):
            return [
                .whileLoop(
                    condition: condition,
                    body: substituteMacroTargetCalls(
                        in: body,
                        targetBinding: targetBinding,
                        targetBlock: targetBlock
                    )
                )
            ]
        case .conditional(let branches):
            return [
                .conditional(
                    branches.map { branch in
                        StatementConditionalBranch(
                            condition: branch.condition,
                            body: substituteMacroTargetCalls(
                                in: branch.body,
                                targetBinding: targetBinding,
                                targetBlock: targetBlock
                            )
                        )
                    }
                )
            ]
        case .switchStatement(let expression, let cases, let defaultBody):
            return [
                .switchStatement(
                    expression: expression,
                    cases: cases.map { switchCase in
                        SwitchCase(
                            value: switchCase.value,
                            body: substituteMacroTargetCalls(
                                in: switchCase.body,
                                targetBinding: targetBinding,
                                targetBlock: targetBlock
                            )
                        )
                    },
                    defaultBody: defaultBody.map {
                        substituteMacroTargetCalls(
                            in: $0,
                            targetBinding: targetBinding,
                            targetBlock: targetBlock
                        )
                    }
                )
            ]
        default:
            return [statement]
        }
    }
}
