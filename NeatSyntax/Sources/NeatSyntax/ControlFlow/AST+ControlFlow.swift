import Foundation

public indirect enum Statement {
    case freestandingMacro(name: String, argumentClause: String?, body: [Statement])
    case localBinding(LocalBindingDeclaration)
    case derived(name: String, typeName: String, body: [Statement])
    case environmentProvision(EnvironmentProvision)
    case assignment(target: AssignmentTarget, expression: Expression)
    case compoundAssignment(
        target: AssignmentTarget,
        operatorSymbol: CompoundOperator,
        expression: Expression
    )
    case expression(Expression)
    case forEach(name: String, sequence: Expression, body: [Statement])
    case whileLoop(condition: Expression, body: [Statement])
    case conditional([StatementConditionalBranch])
    case `return`(Expression?)
    case `break`
    case `continue`
    case switchStatement(
        expression: Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?
    )
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

public struct SwitchCase {
    public let value: Expression
    public let body: [Statement]

    public init(value: Expression, body: [Statement]) {
        self.value = value
        self.body = body
    }
}

public enum LocalBindingKind {
    case constant
    case mutable
}

struct LocalBindingSymbol {
    let kind: LocalBindingKind
    let type: TypeReference
}

public indirect enum AssignmentTarget {
    case state(String)
    case binding(String)
    case environment(String)
    case local(String)
    case member(base: AssignmentTarget, name: String)
}

public enum CompoundOperator: String {
    case plusEquals = "+="
}
