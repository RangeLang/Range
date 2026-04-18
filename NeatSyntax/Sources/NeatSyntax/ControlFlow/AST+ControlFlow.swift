import Foundation

public indirect enum Statement {
    case macroInvocation(name: String, argumentClause: String?, body: [Statement])
    case background(Background)
    case localBinding(LocalBindingDeclaration)
    case localCallable(LocalCallableDeclaration)
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

public struct Background {
    public let body: [Statement]

    public init(body: [Statement]) {
        self.body = body
    }
}

public struct LocalCallableDeclaration {
    public let macros: [MacroApplication]
    public let attribute: AttributeApplication?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let hasExplicitParameterClause: Bool
    public let parameters: [NeatFunctionParameter]
    public let returnType: TypeReference?
    public let body: [Statement]

    public init(
        macros: [MacroApplication],
        attribute: AttributeApplication?,
        name: String,
        genericParameters: [GenericParameter],
        hasExplicitParameterClause: Bool,
        parameters: [NeatFunctionParameter],
        returnType: TypeReference?,
        body: [Statement]
    ) {
        self.macros = macros
        self.attribute = attribute
        self.name = name
        self.genericParameters = genericParameters
        self.hasExplicitParameterClause = hasExplicitParameterClause
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
    }

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
    public let pattern: SwitchCasePattern
    public let body: [Statement]

    public init(pattern: SwitchCasePattern, body: [Statement]) {
        self.pattern = pattern
        self.body = body
    }
}

public enum SwitchCasePattern {
    case expression(Expression)
    case enumCase(name: String, binding: SwitchCaseBinding?)
}

public struct SwitchCaseBinding {
    public let kind: LocalBindingKind
    public let name: String

    public init(kind: LocalBindingKind, name: String) {
        self.kind = kind
        self.name = name
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
