import Foundation
import RangeCompiler

struct SwiftLoweredProgramAdapter {
    private typealias RangeExpression = RangeCompiler.Expression
    private typealias RangeStatement = RangeCompiler.Statement

    func adapt(program: LoweredProgram) -> LoweredProgram {
        .init(
            macrosByName: program.macrosByName,
            callables: program.callables.map(lower(callable:)),
            enumerations: program.enumerations,
            declarations: program.declarations.map(lower(construct:)),
            extensions: program.extensions.map(lower(extension:)),
            mainBlock: lower(mainBlock: program.mainBlock),
            units: program.units.map(lower(sourceUnit:))
        )
    }

    private func lower(sourceUnit: LoweredSourceUnit) -> LoweredSourceUnit {
        .init(
            outputFileName: sourceUnit.outputFileName,
            enumerations: sourceUnit.enumerations,
            declarations: sourceUnit.declarations.map(lower(construct:)),
            extensions: sourceUnit.extensions.map(lower(extension:)),
            callables: sourceUnit.callables.map(lower(callable:)),
            mainBlock: sourceUnit.mainBlock.map(lower(mainBlock:))
        )
    }

    private func lower(mainBlock: MainBlockNode) -> MainBlockNode {
        MainBlockNode(macros: mainBlock.macros, body: lower(statements: mainBlock.body))
    }

    private func lower(construct: ConstructDeclaration) -> ConstructDeclaration {
        ConstructDeclaration(
            macros: construct.macros,
            kind: construct.kind,
            attribute: construct.attribute,
            name: construct.name,
            genericParameters: construct.genericParameters,
            conformances: [],
            states: construct.states,
            bindings: construct.bindings,
            deriveds: construct.deriveds.map(lower(derived:)),
            values: construct.values,
            initializers: construct.initializers.map(lower(initializer:)),
            callables: construct.callables.map(lower(callable:)),
            constructs: construct.constructs.map(lower(construct:))
        )
    }

    private func lower(extension declaration: ExtensionDeclaration) -> ExtensionDeclaration {
        ExtensionDeclaration(
            macros: declaration.macros,
            targetType: declaration.targetType,
            genericArgumentConstraints: declaration.genericArgumentConstraints,
            conformances: [],
            initializers: declaration.initializers.map(lower(initializer:)),
            callables: declaration.callables.map(lower(callable:)),
            constructs: declaration.constructs.map(lower(construct:)),
            enumerations: declaration.enumerations,
            enumCases: declaration.enumCases
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
            returnType: initializer.returnType,
            body: initializer.body.map(lower(statements:))
        )
    }

    private func lower(callable: CallableDeclaration) -> CallableDeclaration {
        CallableDeclaration(
            macros: callable.macros,
            attribute: callable.attribute,
            targetType: callable.targetType,
            receiverType: callable.receiverType,
            name: callable.name,
            genericParameters: callable.genericParameters,
            hasExplicitParameterClause: callable.hasExplicitParameterClause,
            parameters: callable.parameters,
            returnType: callable.returnType,
            body: callable.body.map(lower(statements:))
        )
    }

    private func lower(statements: [RangeStatement]) -> [RangeStatement] {
        statements.map(lower(statement:))
    }

    private func lower(statement: RangeStatement) -> RangeStatement {
        switch statement {
        case .macroInvocation(let name, let argumentClause, let body):
            return .macroInvocation(
                name: name,
                argumentClause: argumentClause,
                body: lower(statements: body)
            )
        case .expand:
            return statement
        case .background(let background):
            return .background(
                Background(macros: background.macros, body: lower(statements: background.body))
            )
        case .deferBlock(let deferred):
            return .deferBlock(DeferredBlock(body: lower(statements: deferred.body)))
        case .localBinding(let declaration):
            return .localBinding(
                LocalBindingDeclaration(
                    kind: declaration.kind,
                    name: declaration.name,
                    hasExplicitTypeAnnotation: declaration.hasExplicitTypeAnnotation,
                    type: declaration.type,
                    expression: lower(expression: declaration.expression)
                )
            )
        case .localCallable(let declaration):
            return .localCallable(
                LocalCallableDeclaration(
                    macros: declaration.macros,
                    attribute: declaration.attribute,
                    name: declaration.name,
                    genericParameters: declaration.genericParameters,
                    hasExplicitParameterClause: declaration.hasExplicitParameterClause,
                    parameters: declaration.parameters,
                    returnType: declaration.returnType,
                    body: lower(statements: declaration.body)
                )
            )
        case .derived(let name, let typeName, let body):
            return .derived(name: name, typeName: typeName, body: lower(statements: body))
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
                        pattern: lower(switchCasePattern: switchCase.pattern),
                        body: lower(statements: switchCase.body)
                    )
                },
                defaultBody: defaultBody.map(lower(statements:))
            )
        }
    }

    private func lower(switchCasePattern: SwitchCasePattern) -> SwitchCasePattern {
        switch switchCasePattern {
        case .expression(let expression):
            return .expression(lower(expression: expression))
        case .enumCase(let name, let binding):
            return .enumCase(name: name, binding: binding)
        }
    }

    private func lower(expression: RangeExpression) -> RangeExpression {
        let lowered: RangeExpression

        switch expression {
        case .macroInvocation:
            lowered = expression
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

    private func lowerCoreScalarLiteralBridge(_ expression: RangeExpression) -> RangeExpression? {
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
