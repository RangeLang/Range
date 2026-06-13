import Foundation

public enum SourceFileNode {
    case construct(ConstructDeclaration)
    case enumeration(EnumDeclaration)
    case macro(MacroDeclaration)
    case mainBlock(MainBlockNode)
    case extensions([ExtensionDeclaration])
    case module(ModuleFileNode)
}

public struct MainBlockNode {
    public let macros: [MacroApplication]
    public let body: [Statement]

    public init(macros: [MacroApplication], body: [Statement]) {
        self.macros = macros
        self.body = body
    }
}

public struct ModuleFileNode {
    public let mainBlock: MainBlockNode?
    public let states: [StateDeclaration]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let enumerations: [EnumDeclaration]
    public let macros: [MacroDeclaration]
    public let precedenceGroups: [PrecedenceGroupDeclaration]
    public let operators: [OperatorDeclaration]
    public let extensions: [ExtensionDeclaration]

    public init(
        mainBlock: MainBlockNode?,
        states: [StateDeclaration],
        callables: [CallableDeclaration],
        constructs: [ConstructDeclaration],
        enumerations: [EnumDeclaration],
        macros: [MacroDeclaration],
        precedenceGroups: [PrecedenceGroupDeclaration],
        operators: [OperatorDeclaration],
        extensions: [ExtensionDeclaration]
    ) {
        self.mainBlock = mainBlock
        self.states = states
        self.callables = callables
        self.constructs = constructs
        self.enumerations = enumerations
        self.macros = macros
        self.precedenceGroups = precedenceGroups
        self.operators = operators
        self.extensions = extensions
    }
}
