import Foundation

public enum GenericParameter {
    case type(name: String, constraint: TypeReference?, defaultArgument: TypeReference?)
    case value(name: String, typeReference: TypeReference, defaultValue: Expression?)
}

public indirect enum TypeReference: Equatable, Sendable {
    case named(String)
    case member(base: TypeReference, name: String)
    case generic(base: TypeReference, arguments: [TypeReference])
    case array(TypeReference)
    case function(parameters: [TypeReference], returnType: TypeReference)
    case optional(TypeReference)
    case variadic(TypeReference)

    public var displayName: String {
        switch self {
        case .named(let name):
            return name
        case .member(let base, let name):
            return "\(base.displayName).\(name)"
        case .generic(let base, let arguments):
            let renderedArguments = arguments.map(\.displayName).joined(separator: ", ")
            return "\(base.displayName)<\(renderedArguments)>"
        case .array(let element):
            return "[\(element.displayName)]"
        case .function(let parameters, let returnType):
            let renderedParameters = parameters.map(\.displayName).joined(separator: ", ")
            return "(\(renderedParameters)) -> \(returnType.displayName)"
        case .optional(let wrapped):
            return "\(wrapped.displayName)?"
        case .variadic(let element):
            return "\(element.displayName)..."
        }
    }
}

public enum BootstrapLiteralType: Equatable, Sendable {
    case intLiteral
    case floatLiteral
    case stringLiteral
    case boolLiteral
    case nilLiteral
    case typed(TypeReference)

    public var displayName: String {
        switch self {
        case .intLiteral:
            return "IntLiteral"
        case .floatLiteral:
            return "FloatLiteral"
        case .stringLiteral:
            return "StringLiteral"
        case .boolLiteral:
            return "BoolLiteral"
        case .nilLiteral:
            return "NilLiteral"
        case .typed(let type):
            return type.displayName
        }
    }

    public var isLiteralLike: Bool {
        switch self {
        case .typed:
            return false
        case .intLiteral, .floatLiteral, .stringLiteral, .boolLiteral, .nilLiteral:
            return true
        }
    }
}
