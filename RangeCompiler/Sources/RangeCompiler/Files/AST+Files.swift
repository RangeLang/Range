import Foundation

public struct ParsedSourceFile {
    public let path: String
    public let source: String?
    public let sourceFile: ModuleFileNode

    public init(path: String, source: String? = nil, sourceFile: ModuleFileNode) {
        self.path = path
        self.source = source
        self.sourceFile = sourceFile
    }
}

public struct BlockMacroNode {
    public let macros: [MacroApplication]
    public let body: [Statement]
    public let rawBody: String

    public init(macros: [MacroApplication], body: [Statement], rawBody: String = "") {
        self.macros = macros
        self.body = body
        self.rawBody = rawBody
    }
}

public struct ModuleFileNode {
    public let blockMacros: [BlockMacroNode]
    public let constructs: [ConstructDeclaration]
    public let enumerations: [EnumDeclaration]
    public let macros: [MacroDeclaration]
    public let extensions: [ExtensionDeclaration]

    public init(
        blockMacros: [BlockMacroNode] = [],
        constructs: [ConstructDeclaration],
        enumerations: [EnumDeclaration],
        macros: [MacroDeclaration],
        extensions: [ExtensionDeclaration]
    ) {
        self.blockMacros = blockMacros
        self.constructs = constructs
        self.enumerations = enumerations
        self.macros = macros
        self.extensions = extensions
    }
}
