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
}
