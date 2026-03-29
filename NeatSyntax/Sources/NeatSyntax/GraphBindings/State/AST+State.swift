import Foundation

public struct StateDeclaration {
    public let macros: [MacroApplication]
    public let name: String
    public let hasExplicitTypeAnnotation: Bool
    public let type: TypeReference
    public let storage: StateStorage

    public init(
        macros: [MacroApplication],
        name: String,
        hasExplicitTypeAnnotation: Bool,
        type: TypeReference,
        storage: StateStorage
    ) {
        self.macros = macros
        self.name = name
        self.hasExplicitTypeAnnotation = hasExplicitTypeAnnotation
        self.type = type
        self.storage = storage
    }
}

public enum StateStorage {
    case stored(Expression)
    case declared
}
