import Foundation

public enum ConstructKind {
    case entry
    case declaration
    case builder
}

public struct ConstructDeclaration {
    public let macros: [MacroApplication]
    public let kind: ConstructKind
    public let attribute: AttributeApplication?
    public let name: String
    public let genericParameters: [GenericParameter]
    public let conformances: [TypeReference]
    public let states: [StateDeclaration]
    public let environments: [EnvironmentDeclaration]
    public let bindings: [BindingDeclaration]
    public let deriveds: [DerivedDeclaration]
    public let values: [ValueDeclaration]
    public let initializers: [InitializerDeclaration]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]

    public init(
        macros: [MacroApplication],
        kind: ConstructKind,
        attribute: AttributeApplication?,
        name: String,
        genericParameters: [GenericParameter],
        conformances: [TypeReference],
        states: [StateDeclaration],
        environments: [EnvironmentDeclaration],
        bindings: [BindingDeclaration],
        deriveds: [DerivedDeclaration],
        values: [ValueDeclaration],
        initializers: [InitializerDeclaration],
        callables: [CallableDeclaration],
        constructs: [ConstructDeclaration]
    ) {
        self.macros = macros
        self.kind = kind
        self.attribute = attribute
        self.name = name
        self.genericParameters = genericParameters
        self.conformances = conformances
        self.states = states
        self.environments = environments
        self.bindings = bindings
        self.deriveds = deriveds
        self.values = values
        self.initializers = initializers
        self.callables = callables
        self.constructs = constructs
    }

    public var isCore: Bool {
        attribute?.isLanguageBoundary == true
    }

    public var isPackaging: Bool {
        attribute?.isPackaging == true
    }
}

public struct AttributeApplication {
    public let name: String
    public let argument: String?

    public init(name: String, argument: String?) {
        self.name = name
        self.argument = argument
    }

    public var isLanguageBoundary: Bool {
        name == "language" || name == "core"
    }

    public var isPackaging: Bool {
        name == "package"
    }
}
