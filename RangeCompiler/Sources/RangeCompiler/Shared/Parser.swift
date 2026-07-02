import Foundation

public struct Parser {
    let tokens: [LexedToken]
    var index: Int = 0
    var currentExpressionTerminators: [Token] = []
    var literalBridgeResolver: LiteralBridgeResolver
    var declarationMemberResolver: DeclarationMemberResolver
    var declarationOperatorResolver: DeclarationOperatorResolver
    var declarationMacroExpansionResolver: DeclarationMacroExpansionResolver
    var macroDeclarationsByName: [String: MacroDeclaration]
    var macroMetadataByName: [String: MacroMetadataDeclaration]
    var macroExpansionTypes: [String: TypeReference] = [:]

    public init(
        source: String,
        literalBridgeResolver: LiteralBridgeResolver = .empty,
        declarationMemberResolver: DeclarationMemberResolver = .empty,
        declarationOperatorResolver: DeclarationOperatorResolver = .empty,
        declarationMacroExpansionResolver: DeclarationMacroExpansionResolver = .empty,
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        macroMetadataByName: [String: MacroMetadataDeclaration] = [:],
        macroExpansionTypes: [String: TypeReference] = [:]
    ) throws {
        let foreignBodies = macroMetadataByName.values.compactMap { metadata -> LexerForeignBody? in
            guard let language = metadata.foreignBodyLanguage else {
                return nil
            }
            return LexerForeignBody(directive: metadata.name, language: language)
        }
        var lexer = Lexer(source: source, foreignBodies: foreignBodies)
        self.tokens = try lexer.tokenize()
        self.literalBridgeResolver = literalBridgeResolver
        self.declarationMemberResolver = declarationMemberResolver
        self.declarationOperatorResolver = declarationOperatorResolver
        self.declarationMacroExpansionResolver = declarationMacroExpansionResolver
        self.macroDeclarationsByName = macroDeclarationsByName.merging(
            ["macro": MacroDeclaration.bootstrapMacroSeed()]
        ) { current, _ in current }
        self.macroMetadataByName = macroMetadataByName
        self.macroExpansionTypes = macroExpansionTypes
    }

    mutating func registerMacroDeclaration(_ declaration: MacroDeclaration) {
        macroDeclarationsByName[declaration.name] = declaration
        declarationMacroExpansionResolver = DeclarationMacroExpansionResolver(
            macrosByName: macroDeclarationsByName
        )
        if let expansionType = declaration.expansionType {
            macroExpansionTypes[declaration.name] = expansionType
        } else {
            macroExpansionTypes.removeValue(forKey: declaration.name)
        }
    }

    mutating func registerMacroMetadataDeclaration(_ declaration: MacroMetadataDeclaration) {
        macroMetadataByName[declaration.name] = declaration
    }

    func macroApplicationHasMetadataSlotEffect(_ application: MacroApplication) -> Bool {
        macroMetadataByName[application.name]?.hasMetadataSlotEffect == true
    }

    func isCurrentExpressionTerminator(_ token: Token) -> Bool {
        currentExpressionTerminators.contains(where: { $0 == token })
    }

    public mutating func parseSourceFile() throws -> ModuleFileNode {
        var blockMacros: [BlockMacroNode] = []
        var macros: [MacroDeclaration] = []

        while peek() != .eof {
            if isMacroDeclarationStart() {
                let declaration = try parseMacroDeclaration()
                macros.append(declaration)
                registerMacroDeclaration(declaration)
                continue
            }

            if isTopLevelBlockMacroStart() {
                blockMacros.append(try parseTopLevelBlockMacro())
                continue
            }

            throw ParseError(
                "Range source accepts only @macro declarations and top-level macro blocks."
            )
        }

        try consume(.eof)

        return ModuleFileNode(
            blockMacros: blockMacros,
            constructs: [],
            enumerations: [],
            macros: macros,
            extensions: []
        )
    }

    public mutating func parseSourceFileForDeclarationDiscovery() throws -> ModuleFileNode {
        var macros: [MacroDeclaration] = []

        while peek() != .eof {
            if isMacroDeclarationStart() {
                let declaration = try parseMacroDeclaration(signatureOnly: true)
                macros.append(declaration)
                registerMacroDeclaration(declaration)
                continue
            }

            if isTopLevelBlockMacroStart() {
                try skipTopLevelBlockMacroForDeclarationDiscovery()
                continue
            }

            throw ParseError(
                "Range source accepts only @macro declarations and top-level macro blocks."
            )
        }

        try consume(.eof)

        return ModuleFileNode(
            constructs: [],
            enumerations: [],
            macros: macros,
            extensions: []
        )
    }

}
