import Foundation

indirect enum CompileTimeValue {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([CompileTimeValue])
    case object(typeName: String, fields: [String: CompileTimeValue])

    func field(_ name: String) -> CompileTimeValue? {
        guard case .object(_, let fields) = self else {
            return nil
        }
        return fields[name]
    }

    var expression: Expression? {
        switch self {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .double(let value):
            return .double(value)
        case .boolean(let value):
            return .boolean(value)
        case .array(let values):
            let elements = values.compactMap(\.expression)
            guard elements.count == values.count else {
                return nil
            }
            return .array(elements)
        case .object(let typeName, let fields):
            let arguments = fields.compactMap { label, value -> CallArgument? in
                guard let expression = value.expression else {
                    return nil
                }
                return CallArgument(label: label, value: expression)
            }
            guard arguments.count == fields.count else {
                return nil
            }
            return .call(name: typeName, arguments: arguments)
        }
    }
}
