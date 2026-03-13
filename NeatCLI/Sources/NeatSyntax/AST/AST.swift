import Foundation

public enum DeclarationKind {
    case app
    case page
    case component
}

public enum ObjectType {
    case neatFunction(NeatFunctionDeclaration)
    case typeExtension(TypeExtensionDeclaration)
    case neatProtocol(ProtocolDeclaration)
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
    public let members: [MemberDeclaration]
    public let callables: [CallableDeclaration]
    public let body: ViewNode?

    public var neatFunctions: [NeatFunctionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension, .neatProtocol:
                return nil
            case .neatFunction(let function):
                return function
            }
        }
    }

    public var typeExtensions: [TypeExtensionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension(let declaration):
                return declaration
            case .neatFunction, .neatProtocol:
                return nil
            }
        }
    }

    public var protocols: [ProtocolDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatProtocol(let declaration):
                return declaration
            case .neatFunction, .typeExtension:
                return nil
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
    public let callables: [CallableDeclaration]
    public let body: ViewNode

    public var neatFunctions: [NeatFunctionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension, .neatProtocol:
                return nil
            case .neatFunction(let function):
                return function
            }
        }
    }

    public var typeExtensions: [TypeExtensionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension(let declaration):
                return declaration
            case .neatFunction, .neatProtocol:
                return nil
            }
        }
    }

    public var protocols: [ProtocolDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatProtocol(let declaration):
                return declaration
            case .neatFunction, .typeExtension:
                return nil
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

public struct NeatFunctionDeclaration {
    public let name: String
    public let parameters: [NeatFunctionParameter]
    public let returnType: String?
}

public struct NeatFunctionParameter {
    public let name: String
    public let typeName: String?
}

public struct CallableDeclaration {
    public let name: String
    public let parameters: [NeatFunctionParameter]
    public let hasBody: Bool
}

public struct TypeExtensionDeclaration {
    public let typeName: String
}

public struct ProtocolDeclaration {
    public let name: String
    public let requirements: [ProtocolRequirement]
}

public struct AttributeApplication {
    public let name: String
    public let argument: String?
}

public struct MemberDeclaration {
    public let name: String
    public let typeName: String
}

public enum ProtocolRequirement {
    case member(MemberRequirement)
    case function(FunctionRequirement)
    case callable(CallableRequirement)
}

public struct MemberRequirement {
    public let name: String
    public let typeName: String
    public let defaultValue: Expression?
}

public struct FunctionRequirement {
    public let name: String
    public let parameters: [NeatFunctionParameter]
    public let returnType: String?
}

public struct CallableRequirement {
    public let name: String
    public let parameters: [NeatFunctionParameter]
    public let hasDefaultImplementation: Bool
}

public struct StateDeclaration {
    public let name: String
    public let type: BuiltinType
    public let initialValue: Expression
}

public enum BuiltinType: String {
    case int = "Int"
    case string = "String"
    case bool = "Bool"
    case dictionary = "Dictionary"
    case void = "Void"
}

public indirect enum ViewNode {
    case text(InterpolatedString)
    case button(title: String, action: [Statement])
    case component(name: String, children: [ViewNode]?)
    case element(tag: String, children: [ViewNode])
    case forEach(name: String, sequence: Expression, body: [ViewNode])
    case slot(name: String)
    case vStack([ViewNode])
    case debugPrint(InterpolatedString)
    case modified(base: ViewNode, modifiers: [ModifierCall])
}

public struct ModifierCall {
    public let name: String
    public let arguments: [ModifierCallArgument]
}

public struct ModifierCallArgument {
    public let label: String?
    public let value: ModifierArgument
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
    case forEach(name: String, sequence: Expression, body: [Statement])
    case switchStatement(
        expression: Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?
    )
    case debugPrint(InterpolatedString)
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
    case local(String)
}

public enum CompoundOperator: String {
    case plusEquals = "+="
}

public indirect enum Expression {
    case integer(Int)
    case string(String)
    case boolean(Bool)
    case identifier(String)
    case array([Expression])
    case binary(lhs: Expression, operatorSymbol: BinaryOperator, rhs: Expression)
}

public enum BinaryOperator: String {
    case addition = "+"
}
