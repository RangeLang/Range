import RangeCompiler

indirect enum SwiftEmissionStatement {
    case emitted(String)
    case ignored
    case localBinding(LocalBindingDeclaration)
    case assignment(target: AssignmentTarget, expression: Expression)
    case expression(Expression)
    case whileLoop(condition: Expression, body: [SwiftEmissionStatement])
    case conditional([SwiftEmissionConditionalBranch])
    case `return`(Expression?)

    init(source statement: Statement) throws {
        switch statement {
        case .emitted(let text):
            self = .emitted(text)
        case .macroApplication:
            self = .ignored
        case .macroInvocation:
            throw SwiftBackendError("Macro invocations must be expanded before Swift emission.")
        case .localBinding(let declaration):
            self = .localBinding(declaration)
        case .assignment(let target, let expression):
            self = .assignment(target: target, expression: expression)
        case .expression(let expression):
            self = .expression(expression)
        case .whileLoop(let condition, let body):
            self = .whileLoop(
                condition: condition,
                body: try body.map(SwiftEmissionStatement.init(source:))
            )
        case .conditional(let branches):
            self = .conditional(try branches.map(SwiftEmissionConditionalBranch.init(source:)))
        case .return(let expression):
            self = .return(expression)
        }
    }
}

struct SwiftEmissionConditionalBranch {
    let condition: Expression?
    let body: [SwiftEmissionStatement]

    init(condition: Expression?, body: [SwiftEmissionStatement]) {
        self.condition = condition
        self.body = body
    }

    init(source branch: StatementConditionalBranch) throws {
        self.condition = branch.condition
        self.body = try branch.body.map(SwiftEmissionStatement.init(source:))
    }
}
