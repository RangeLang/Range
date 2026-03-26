import Foundation

public enum GenericParameter {
    case type(name: String, constraint: TypeReference?, defaultArgument: TypeReference?)
    case value(name: String, typeReference: TypeReference, defaultValue: Expression?)
}

public indirect enum TypeReference: Equatable {
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

public indirect enum BuiltinType: Equatable {
    case int
    case double
    case float
    case string
    case bool
    case data
    case dictionary
    case set(BuiltinType)
    case void
    case none
    case optional(BuiltinType)

    public var displayName: String {
        switch self {
        case .int:
            return "Int"
        case .double:
            return "Double"
        case .float:
            return "Float"
        case .string:
            return "String"
        case .bool:
            return "Bool"
        case .data:
            return "Data"
        case .dictionary:
            return "Dictionary"
        case .set(let element):
            return "Set<\(element.displayName)>"
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
