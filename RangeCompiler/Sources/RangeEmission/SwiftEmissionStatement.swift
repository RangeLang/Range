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
}
