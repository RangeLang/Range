import Foundation

public enum SourceFileNode {
    case construct(ConstructDeclaration)
    case namespace(NamespaceDeclaration)
    case enumeration(EnumDeclaration)
    case protocolDefinition(ProtocolDeclaration)
    case macro(MacroDeclaration)
    case mainBlock(MainBlockNode)
    case extensions([ExtensionDeclaration])
    case module(ModuleFileNode)
}

public struct MainBlockNode {
    public let body: [Statement]

    public init(body: [Statement]) {
        self.body = body
    }
}

public struct ModuleFileNode {
    public let mainBlock: MainBlockNode?
    public let states: [StateDeclaration]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let namespaces: [NamespaceDeclaration]
    public let enumerations: [EnumDeclaration]
    public let protocols: [ProtocolDeclaration]
    public let macros: [MacroDeclaration]
    public let precedenceGroups: [PrecedenceGroupDeclaration]
    public let operators: [OperatorDeclaration]
    public let extensions: [ExtensionDeclaration]

    public init(
        mainBlock: MainBlockNode?,
        states: [StateDeclaration],
        callables: [CallableDeclaration],
        constructs: [ConstructDeclaration],
        namespaces: [NamespaceDeclaration],
        enumerations: [EnumDeclaration],
        protocols: [ProtocolDeclaration],
        macros: [MacroDeclaration],
        precedenceGroups: [PrecedenceGroupDeclaration],
        operators: [OperatorDeclaration],
        extensions: [ExtensionDeclaration]
    ) {
        self.mainBlock = mainBlock
        self.states = states
        self.callables = callables
        self.constructs = constructs
        self.namespaces = namespaces
        self.enumerations = enumerations
        self.protocols = protocols
        self.macros = macros
        self.precedenceGroups = precedenceGroups
        self.operators = operators
        self.extensions = extensions
    }
}
