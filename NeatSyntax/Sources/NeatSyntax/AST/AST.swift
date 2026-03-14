import Foundation

public enum DeclarationKind {
    case entry
    case declaration
}

public enum SourceFileNode {
    case declaration(DeclarationNode)
    case mainBlock(MainBlockNode)
}

public struct MainBlockNode {
    public let body: [Statement]
}

public enum ObjectType {
    case typeExtension(TypeExtensionDeclaration)
}

public struct DeclarationNode {
    public let kind: DeclarationKind
    public let attribute: AttributeApplication?
    public let name: String
    public let conformances: [String]
    public let projectionTarget: String?
    public let objects: [ObjectType]
    public let cases: [EnumCaseDeclaration]
    public let states: [StateDeclaration]
    public let bindings: [BindingDeclaration]
    public let members: [MemberDeclaration]
    public let initializers: [InitializerDeclaration]
    public let callables: [CallableDeclaration]
    public let body: ViewNode?

    public var typeExtensions: [TypeExtensionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension(let declaration):
                return declaration
            }
        }
    }
}

public struct ComponentNode {
    public let kind: DeclarationKind
    public let attribute: AttributeApplication?
    public let objects: [ObjectType]
    public let name: String
    public let conformances: [String]
    public let projectionTarget: String?
    public let cases: [EnumCaseDeclaration]
    public let states: [StateDeclaration]
    public let bindings: [BindingDeclaration]
    public let members: [MemberDeclaration]
    public let initializers: [InitializerDeclaration]
    public let callables: [CallableDeclaration]
    public let body: ViewNode

    public var typeExtensions: [TypeExtensionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension(let declaration):
                return declaration
            }
        }
    }
}

public struct EnumCaseDeclaration {
    public let name: String
    public let associatedValues: [AssociatedValueDeclaration]
}

public struct AssociatedValueDeclaration {
    public let label: String?
    public let typeName: String
}

public struct NeatFunctionParameter {
    public let localName: String
    public let externalLabel: String?
    public let typeName: String?

    public var name: String {
        localName
    }

    public var isOptional: Bool {
        guard let typeName else { return false }
        return typeName.hasSuffix("?")
    }
}

public struct CallableDeclaration {
    public let targetName: String?
    public let name: String
    public let parameters: [NeatFunctionParameter]
    public let body: [Statement]?
}

public struct InitializerDeclaration {
    public let parameters: [NeatFunctionParameter]
    public let body: [Statement]?
}

public struct TypeExtensionDeclaration {
    public let typeName: String
}

public struct AttributeApplication {
    public let name: String
    public let argument: String?
}

public struct MemberDeclaration {
    public let name: String
    public let typeName: String
    public let value: Expression?
}

public struct BindingDeclaration {
    public let name: String
    public let typeName: String
    public let storage: BindingStorage
}

public struct StateDeclaration {
    public let name: String
    public let type: BuiltinType
    public let storage: StateStorage
}

public enum StateStorage {
    case stored(Expression)
    case derived([Statement])
}

public enum BindingStorage {
    case plain
    case derived(get: [Statement], set: [Statement])
}

public indirect enum BuiltinType: Equatable {
    case int
    case string
    case bool
    case dictionary
    case void
    case none
    case optional(BuiltinType)

    public var displayName: String {
        switch self {
        case .int:
            return "Int"
        case .string:
            return "String"
        case .bool:
            return "Bool"
        case .dictionary:
            return "Dictionary"
        case .void:
            return "Void"
        case .none:
            return "none"
        case .optional(let wrapped):
            return "\(wrapped.displayName)?"
        }
    }

    public var isOptional: Bool {
        if case .optional = self {
            return true
        }
        return false
    }
}

public indirect enum ViewNode {
    case text(InterpolatedString)
    case button(title: String, action: [Statement])
    case component(name: String, arguments: [CallArgument], children: [ViewNode]?)
    case element(tag: String, children: [ViewNode])
    case forEach(name: String, sequence: Expression, body: [ViewNode])
    case conditional([ViewConditionalBranch])
    case slot(name: String)
    case vStack([ViewNode])
    case modified(base: ViewNode, modifiers: [ModifierCall])
}

public struct ViewConditionalBranch {
    public let condition: Expression?
    public let body: [ViewNode]
}

public struct ModifierCall {
    public let name: String
    public let arguments: [ModifierCallArgument]
}

public struct ModifierCallArgument {
    public let label: String?
    public let value: ModifierArgument
}

public struct CallArgument {
    public let label: String?
    public let value: Expression
}

public enum ModifierArgument {
    case enumCase(String)
    case enumCall(name: String, arguments: [ModifierArgument])
    case string(String)
    case integer(Int)
    case double(Double)
    case percentage(Double)
    case identifier(String)
}

public struct InterpolatedString {
    public let segments: [StringSegment]
}

public indirect enum StringSegment {
    case text(String)
    case expression(Expression)
}

public indirect enum Statement {
    case declaration(kind: LocalBindingKind, name: String, expression: Expression)
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

public struct StatementConditionalBranch {
    public let condition: Expression?
    public let body: [Statement]
}

public struct SwitchCase {
    public let value: Expression
    public let body: [Statement]
}

public enum LocalBindingKind {
    case constant
    case mutable
}

public enum AssignmentTarget {
    case state(String)
    case binding(String)
    case local(String)
}

public enum CompoundOperator: String {
    case plusEquals = "+="
}

public indirect enum Expression {
    case integer(Int)
    case double(Double)
    case string(String)
    case boolean(Bool)
    case none
    case identifier(String)
    case call(name: String, arguments: [CallArgument])
    case bindingReference(String)
    case array([Expression])
    case ternary(condition: Expression, trueExpression: Expression, falseExpression: Expression)
    case unary(operatorSymbol: UnaryOperator, expression: Expression)
    case binary(lhs: Expression, operatorSymbol: BinaryOperator, rhs: Expression)
}

public enum UnaryOperator: String {
    case not = "!"
}

public enum BinaryOperator: String {
    case addition = "+"
    case equal = "=="
    case notEqual = "!="
    case less = "<"
    case lessEqual = "<="
    case greater = ">"
    case greaterEqual = ">="
    case and = "&&"
    case or = "||"
}
