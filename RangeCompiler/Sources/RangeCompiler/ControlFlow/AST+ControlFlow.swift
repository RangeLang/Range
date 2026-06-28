import Foundation

public indirect enum Statement {
    case emitted(String)
    case macroApplication(name: String, arguments: [CallArgument])
    case macroInvocation(name: String, argumentClause: String?, body: [Statement])
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
