import Foundation

public enum SourceFileNode {
    case construct(ConstructDeclaration)
    case enumeration(EnumDeclaration)
    case protocolDefinition(ProtocolDeclaration)
    case macro(MacroDeclaration)
    case mainBlock(MainBlockNode)
    case extensions([ExtensionDeclaration])
    case module(ModuleFileNode)
}

public struct MainBlockNode {
    public let body: [Statement]
}

public struct ModuleFileNode {
    public let states: [StateDeclaration]
    public let callables: [CallableDeclaration]
    public let constructs: [ConstructDeclaration]
    public let enumerations: [EnumDeclaration]
    public let protocols: [ProtocolDeclaration]
    public let macros: [MacroDeclaration]
    public let extensions: [ExtensionDeclaration]
}
