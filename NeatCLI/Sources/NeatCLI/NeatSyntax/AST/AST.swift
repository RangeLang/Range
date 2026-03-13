import Foundation

enum DeclarationKind {
    case app
    case page
    case component
}

enum ObjectType {
    case neatEnum(EnumDeclaration)
    case neatFunction(NeatFunctionDeclaration)
    case styleModifier(StyleModifierDeclaration)
    case typeExtension(TypeExtensionDeclaration)
    case neatProtocol(ProtocolDeclaration)
}

struct DeclarationNode {
    let kind: DeclarationKind
    let attribute: AttributeApplication?
    let name: String
    let conformances: [String]
    let objects: [ObjectType]
    let states: [StateDeclaration]
    let members: [MemberDeclaration]
    let initializers: [InitDeclaration]
    let body: ViewNode?

    var enums: [EnumDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatEnum(let declaration):
                return declaration
            case .neatFunction, .styleModifier, .typeExtension, .neatProtocol:
                return nil
            }
        }
    }

    var neatFunctions: [NeatFunctionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatEnum, .styleModifier, .typeExtension, .neatProtocol:
                return nil
            case .neatFunction(let function):
                return function
            }
        }
    }

    var styleModifiers: [StyleModifierDeclaration] {
        objects.compactMap { object in
            switch object {
            case .styleModifier(let styleModifier):
                return styleModifier
            case .neatEnum, .neatFunction, .typeExtension, .neatProtocol:
                return nil
            }
        }
    }

    var typeExtensions: [TypeExtensionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension(let declaration):
                return declaration
            case .neatEnum, .neatFunction, .styleModifier, .neatProtocol:
                return nil
            }
        }
    }

    var protocols: [ProtocolDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatProtocol(let declaration):
                return declaration
            case .neatEnum, .neatFunction, .styleModifier, .typeExtension:
                return nil
            }
        }
    }
}

struct ComponentNode {
    let kind: DeclarationKind
    let attribute: AttributeApplication?
    let objects: [ObjectType]
    let name: String
    let conformances: [String]
    let states: [StateDeclaration]
    let initializers: [InitDeclaration]
    let body: ViewNode

    var enums: [EnumDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatEnum(let declaration):
                return declaration
            case .neatFunction, .styleModifier, .typeExtension, .neatProtocol:
                return nil
            }
        }
    }

    var neatFunctions: [NeatFunctionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatEnum, .styleModifier, .typeExtension, .neatProtocol:
                return nil
            case .neatFunction(let function):
                return function
            }
        }
    }

    var styleModifiers: [StyleModifierDeclaration] {
        objects.compactMap { object in
            switch object {
            case .styleModifier(let styleModifier):
                return styleModifier
            case .neatEnum, .neatFunction, .typeExtension, .neatProtocol:
                return nil
            }
        }
    }

    var typeExtensions: [TypeExtensionDeclaration] {
        objects.compactMap { object in
            switch object {
            case .typeExtension(let declaration):
                return declaration
            case .neatEnum, .neatFunction, .styleModifier, .neatProtocol:
                return nil
            }
        }
    }

    var protocols: [ProtocolDeclaration] {
        objects.compactMap { object in
            switch object {
            case .neatProtocol(let declaration):
                return declaration
            case .neatEnum, .neatFunction, .styleModifier, .typeExtension:
                return nil
            }
        }
    }
}

struct EnumDeclaration {
    let name: String
    let cases: [EnumCaseDeclaration]
}

struct EnumCaseDeclaration {
    let name: String
    let associatedValues: [AssociatedValueDeclaration]
}

struct AssociatedValueDeclaration {
    let label: String?
    let typeName: String
}

struct NeatFunctionDeclaration {
    let name: String
    let parameters: [NeatFunctionParameter]
    let returnType: String?
}

struct NeatFunctionParameter {
    let name: String
    let typeName: String?
}

struct InitDeclaration {
    let parameters: [NeatFunctionParameter]
    let hasBody: Bool
}

struct StyleModifierDeclaration {
    let name: String
    let parameters: [StyleModifierParameter]
}

struct StyleModifierParameter {
    let name: String
    let typeName: String
}

struct TypeExtensionDeclaration {
    let typeName: String
}

struct ProtocolDeclaration {
    let name: String
    let requirements: [ProtocolRequirement]
}

struct AttributeApplication {
    let name: String
    let argument: String?
}

struct MemberDeclaration {
    let name: String
    let typeName: String
}

enum ProtocolRequirement {
    case member(MemberRequirement)
    case function(FunctionRequirement)
    case initializer(InitRequirement)
}

struct MemberRequirement {
    let name: String
    let typeName: String
    let defaultValue: Expression?
}

struct FunctionRequirement {
    let name: String
    let parameters: [NeatFunctionParameter]
    let returnType: String?
}

struct InitRequirement {
    let parameters: [NeatFunctionParameter]
    let hasDefaultImplementation: Bool
}

struct StateDeclaration {
    let name: String
    let type: BuiltinType
    let initialValue: Expression
}

enum BuiltinType: String {
    case int = "Int"
    case string = "String"
    case bool = "Bool"
    case dictionary = "Dictionary"
    case void = "Void"
}

indirect enum ViewNode {
    case text(InterpolatedString)
    case button(title: String, action: [Statement])
    case component(name: String, children: [ViewNode]?)
    case element(tag: String, children: [ViewNode])
    case slot(name: String)
    case vStack([ViewNode])
    case debugPrint(InterpolatedString)
    case modified(base: ViewNode, modifiers: [ModifierCall])
}

struct ModifierCall {
    let name: String
    let arguments: [ModifierCallArgument]
}

struct ModifierCallArgument {
    let label: String?
    let value: ModifierArgument
}

enum ModifierArgument {
    case enumCase(String)
    case enumCall(name: String, arguments: [ModifierArgument])
    case string(String)
    case integer(Int)
    case double(Double)
    case percentage(Double)
    case identifier(String)
}

struct InterpolatedString {
    let segments: [StringSegment]
}

indirect enum StringSegment {
    case text(String)
    case expression(Expression)
}

indirect enum Statement {
    case declaration(kind: LocalBindingKind, name: String, expression: Expression)
    case assignment(target: AssignmentTarget, expression: Expression)
    case compoundAssignment(
        target: AssignmentTarget,
        operatorSymbol: CompoundOperator,
        expression: Expression
    )
    case switchStatement(
        expression: Expression,
        cases: [SwitchCase],
        defaultBody: [Statement]?
    )
    case debugPrint(InterpolatedString)
}

struct SwitchCase {
    let value: Expression
    let body: [Statement]
}

enum LocalBindingKind {
    case constant
    case mutable
}

enum AssignmentTarget {
    case state(String)
    case local(String)
}

enum CompoundOperator: String {
    case plusEquals = "+="
}

indirect enum Expression {
    case integer(Int)
    case string(String)
    case boolean(Bool)
    case identifier(String)
    case array([Expression])
    case binary(lhs: Expression, operatorSymbol: BinaryOperator, rhs: Expression)
}

enum BinaryOperator: String {
    case addition = "+"
}
