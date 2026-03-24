import Foundation

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
