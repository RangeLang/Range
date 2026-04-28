import Foundation

public struct ExtensionGenericArgumentConstraint: Sendable, Equatable {
    public let parameterName: String
    public let constraint: TypeReference
}

public struct ExtensionDeclaration {
    public let macros: [MacroApplication]
    public let targetType: TypeReference
    public let genericArgumentConstraints: [ExtensionGenericArgumentConstraint]
    public let conformances: [TypeReference]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]
    public let enumerations: [EnumDeclaration]
    public let protocols: [ProtocolDeclaration]

    public var usesSpecializedTarget: Bool {
        if !genericArgumentConstraints.isEmpty {
            return true
        }
        if case .generic = targetType {
            return true
        }
        return false
    }

    public var targetName: String {
        switch targetType {
        case .named(let name):
            return name
        case .member:
            return targetType.displayName
        case .generic(let base, _):
            return Self.nominalName(of: base)
        case .array:
            return "Array"
        case .optional:
            return "Optional"
        case .function, .variadic:
            return targetType.displayName
        }
    }

    private static func nominalName(of type: TypeReference) -> String {
        switch type {
        case .named(let name):
            return name
        case .member:
            return type.displayName
        case .generic(let base, _):
            return nominalName(of: base)
        case .array:
            return "Array"
        case .optional:
            return "Optional"
        case .function, .variadic:
            return type.displayName
        }
    }
}
