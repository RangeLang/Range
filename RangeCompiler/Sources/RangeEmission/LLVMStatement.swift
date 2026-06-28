import RangeCompiler

indirect enum LLVMStatement {
    case emitted(String)
    case ignored
    case localBinding(LocalBindingDeclaration)
    case assignment(target: AssignmentTarget, expression: Expression)
    case expression(Expression)
    case whileLoop(condition: Expression, body: [LLVMStatement])
    case conditional([LLVMConditionalBranch])
    case `return`(Expression?)

    init(source statement: Statement) throws {
        switch statement {
        case .emitted(let text):
            self = .emitted(text)
        case .macroApplication:
            self = .ignored
        case .macroInvocation:
            throw LLVMLoweringError("LLVM lowering does not support statement \(statement).")
        case .localBinding(let declaration):
            self = .localBinding(declaration)
        case .assignment(let target, let expression):
            self = .assignment(target: target, expression: expression)
        case .expression(let expression):
            self = .expression(expression)
        case .whileLoop(let condition, let body):
            self = .whileLoop(
                condition: condition,
                body: try body.map(LLVMStatement.init(source:))
            )
        case .conditional(let branches):
            self = .conditional(try branches.map(LLVMConditionalBranch.init(source:)))
        case .return(let expression):
            self = .return(expression)
        }
    }
}

struct LLVMConditionalBranch {
    let condition: Expression?
    let body: [LLVMStatement]

    init(condition: Expression?, body: [LLVMStatement]) {
        self.condition = condition
        self.body = body
    }

    init(source branch: StatementConditionalBranch) throws {
        self.condition = branch.condition
        self.body = try branch.body.map(LLVMStatement.init(source:))
    }
}
