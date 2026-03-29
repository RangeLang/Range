import Foundation
import NeatSyntax

struct SwiftBackendLowerer {
    private typealias NeatExpression = NeatSyntax.Expression
    private typealias NeatStatement = NeatSyntax.Statement

    func lower(program: SwiftBackendEmitter.Program) -> SwiftBackendEmitter.Program {
        .init(
            callables: program.callables.map(lower(callable:)),
            declarations: program.declarations.map(lower(construct:)),
            mainBlock: lower(mainBlock: program.mainBlock),
            units: program.units.map(lower(sourceUnit:))
        )
    }

    private func lower(sourceUnit: SwiftBackendEmitter.SourceUnit) -> SwiftBackendEmitter.SourceUnit
    {
        .init(
            swiftFileName: sourceUnit.swiftFileName,
            callables: sourceUnit.callables.map(lower(callable:)),
            mainBlock: sourceUnit.mainBlock.map(lower(mainBlock:))
        )
    }

    private func lower(mainBlock: MainBlockNode) -> MainBlockNode {
        MainBlockNode(body: lower(statements: mainBlock.body))
    }

    private func lower(construct: ConstructDeclaration) -> ConstructDeclaration {
        ConstructDeclaration(
            macros: construct.macros,
            kind: construct.kind,
            attribute: construct.attribute,
            name: construct.name,
            genericParameters: construct.genericParameters,
            conformances: construct.conformances,
            states: construct.states,
            environments: construct.environments,
            bindings: construct.bindings,
            deriveds: construct.deriveds.map(lower(derived:)),
            values: construct.values,
            initializers: construct.initializers.map(lower(initializer:)),
            callables: construct.callables.map(lower(callable:))
        )
    }

    private func lower(derived: DerivedDeclaration) -> DerivedDeclaration {
        DerivedDeclaration(
            macros: derived.macros,
            builderName: derived.builderName,
            name: derived.name,
            typeName: derived.typeName,
            body: derived.body.map(lower(statements:))
        )
    }

    private func lower(initializer: InitializerDeclaration) -> InitializerDeclaration {
        InitializerDeclaration(
            macros: initializer.macros,
            parameters: initializer.parameters,
            body: initializer.body.map(lower(statements:))
        )
    }

    private func lower(callable: CallableDeclaration) -> CallableDeclaration {
        CallableDeclaration(
            macros: callable.macros,
            targetType: callable.targetType,
            name: callable.name,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: callable.parameters,
            returnType: callable.returnType,
            body: callable.body.map(lower(statements:))
        )
    }

    private func lower(statements: [NeatStatement]) -> [NeatStatement] {
        statements.map(lower(statement:))
    }

    private func lower(statement: NeatStatement) -> NeatStatement {
        switch statement {
        case .freestandingMacro(let name, let argumentClause, let body):
            return .freestandingMacro(
                name: name,
                argumentClause: argumentClause,
                body: lower(statements: body)
            )
        case .declaration(let kind, let name, let typeName, let expression):
            return .declaration(
                kind: kind,
                name: name,
                typeName: typeName,
                expression: lower(expression: expression)
            )
        case .derived(let name, let typeName, let body):
            return .derived(name: name, typeName: typeName, body: lower(statements: body))
        case .environmentProvision:
            return statement
        case .assignment(let target, let expression):
            return .assignment(target: target, expression: lower(expression: expression))
        case .compoundAssignment(let target, let operatorSymbol, let expression):
            return .compoundAssignment(
                target: target,
                operatorSymbol: operatorSymbol,
                expression: lower(expression: expression)
            )
        case .expression(let expression):
            return .expression(lower(expression: expression))
        case .forEach(let name, let sequence, let body):
            return .forEach(
                name: name,
                sequence: lower(expression: sequence),
                body: lower(statements: body)
            )
        case .whileLoop(let condition, let body):
            return .whileLoop(
                condition: lower(expression: condition), body: lower(statements: body))
        case .conditional(let branches):
            return .conditional(
                branches.map { branch in
                    StatementConditionalBranch(
                        condition: branch.condition.map(lower(expression:)),
                        body: lower(statements: branch.body)
                    )
                }
            )
        case .return(let expression):
            return .return(expression.map(lower(expression:)))
        case .break, .continue:
            return statement
        case .switchStatement(let expression, let cases, let defaultBody):
            return .switchStatement(
                expression: lower(expression: expression),
                cases: cases.map { switchCase in
                    SwitchCase(
                        value: lower(expression: switchCase.value),
                        body: lower(statements: switchCase.body)
                    )
                },
                defaultBody: defaultBody.map(lower(statements:))
            )
        }
    }

    private func lower(expression: NeatExpression) -> NeatExpression {
        let lowered: NeatExpression

        switch expression {
        case .call(let name, let arguments):
            lowered = .call(
                name: name,
                arguments: arguments.map { argument in
                    CallArgument(
                        label: argument.label,
                        value: lower(expression: argument.value)
                    )
                }
            )
        case .block(let body):
            lowered = .block(lower(statements: body))
        case .array(let elements):
            lowered = .array(elements.map { lower(expression: $0) })
        case .dictionary(let elements):
            lowered = .dictionary(
                elements.map { element in
                    DictionaryElement(
                        key: lower(expression: element.key),
                        value: lower(expression: element.value)
                    )
                }
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            lowered = .ternary(
                condition: lower(expression: condition),
                trueExpression: lower(expression: trueExpression),
                falseExpression: lower(expression: falseExpression)
            )
        case .unary(let operatorSymbol, let nested):
            lowered = .unary(operatorSymbol: operatorSymbol, expression: lower(expression: nested))
        case .binary(let lhs, let operatorSymbol, let rhs):
            lowered = .binary(
                lhs: lower(expression: lhs),
                operatorSymbol: operatorSymbol,
                rhs: lower(expression: rhs)
            )
        case .interpolatedString(let string):
            lowered = .interpolatedString(
                InterpolatedString(
                    segments: string.segments.map { segment in
                        switch segment {
                        case .text:
                            return segment
                        case .expression(let nested):
                            return .expression(lower(expression: nested))
                        }
                    }
                )
            )
        case .integer, .double, .string, .boolean, .nilLiteral, .identifier, .bindingReference:
            lowered = expression
        }

        if let collapsed = lowerCoreScalarLiteralBridge(lowered) {
            return collapsed
        }
        return lowered
    }

    private func lowerCoreScalarLiteralBridge(_ expression: NeatExpression) -> NeatExpression? {
        guard case .call(let name, let arguments) = expression,
            arguments.count == 1,
            arguments[0].label == "literal"
        else {
            return nil
        }

        let value = arguments[0].value

        switch (name, value) {
        case ("Int", .integer),
            ("String", .string),
            ("String", .interpolatedString),
            ("Bool", .boolean),
            ("Float", .double),
            ("Double", .double),
            ("Optional", .nilLiteral):
            return value
        default:
            return nil
        }
    }
}
