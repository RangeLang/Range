import Foundation

public indirect enum Statement {
    case emitted(String)
    case macroApplication(name: String, arguments: [CallArgument])
    case macroInvocation(name: String, argumentClause: String?, body: [Statement])
    case localBinding(LocalBindingDeclaration)
    case assignment(target: AssignmentTarget, expression: Expression)
    case expression(Expression)
    case whileLoop(condition: Expression, body: [Statement])
    case conditional([StatementConditionalBranch])
    case `return`(Expression?)
}

public struct LocalBindingDeclaration {
    public let kind: LocalBindingKind
    public let name: String
    public let hasExplicitTypeAnnotation: Bool
    public let type: TypeReference
    public let expression: Expression

    public init(
        kind: LocalBindingKind,
        name: String,
        hasExplicitTypeAnnotation: Bool,
        type: TypeReference,
        expression: Expression
    ) {
        self.kind = kind
        self.name = name
        self.hasExplicitTypeAnnotation = hasExplicitTypeAnnotation
        self.type = type
        self.expression = expression
    }
}

public struct StatementConditionalBranch {
    public let condition: Expression?
    public let body: [Statement]

    public init(condition: Expression?, body: [Statement]) {
        self.condition = condition
        self.body = body
    }
}

public enum LocalBindingKind {
    case constant
    case mutable
}

public indirect enum AssignmentTarget {
    case state(String)
    case binding(String)
    case local(String)
    case member(base: AssignmentTarget, name: String)
}
