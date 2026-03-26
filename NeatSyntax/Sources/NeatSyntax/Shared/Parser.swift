import Foundation

public struct Parser {
    let tokens: [Token]
    var index: Int = 0
    var currentStateNames: Set<String> = []
    var currentMutableStateNames: Set<String> = []
    var currentStateTypes: [String: TypeReference] = [:]
    var currentEnvironmentTypes: [String: BuiltinType] = [:]
    var currentBindingNames: Set<String> = []
    var currentEnvironmentNames: Set<String> = []
    var currentMutableEnvironmentNames: Set<String> = []
    var currentSelfAvailable: Bool = false
    var currentExpressionTerminators: [Token] = []

    public init(source: String) throws {
        var lexer = Lexer(source: source)
        self.tokens = try lexer.tokenize()
    }

    func isCurrentExpressionTerminator(_ token: Token) -> Bool {
        currentExpressionTerminators.contains(where: { $0 == token })
    }

    public mutating func parseSourceFile() throws -> SourceFileNode {
        currentStateTypes = [:]

        var mainBlock: MainBlockNode?
        var topLevelStates: [StateDeclaration] = []
        var topLevelCallables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var protocols: [ProtocolDeclaration] = []
        var macros: [MacroDeclaration] = []
        var extensions: [ExtensionDeclaration] = []

        while peek() != .eof {
            if isMainBlockStart() {
                guard mainBlock == nil else {
                    throw ParseError("Only one @main block is allowed per file.")
                }
                mainBlock = try parseMainBlock(requiresEOF: false)
                continue
            }

            if peek() == .keyword(NeatSyntax.Keyword.typeExtension.rawValue) {
                extensions.append(try parseExtensionDeclaration())
                continue
            }

            if peek() == .keyword(NeatSyntax.Keyword.state.rawValue) {
                let state = try parseState()
                topLevelStates.append(state)
                currentStateTypes[state.name] = state.type
                continue
            }

            if isCallableStart() {
                topLevelCallables.append(try parseCallableDeclaration())
                continue
            }

            if isEnumDeclarationStart() {
                enumerations.append(try parseEnumDeclaration(requiresEOF: false))
                continue
            }

            if isProtocolDeclarationStart() {
                protocols.append(try parseProtocolDeclaration(requiresEOF: false))
                continue
            }

            if isMacroDeclarationStart() {
                macros.append(try parseMacroDeclaration())
                continue
            }

            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                constructs.append(try parseConstructDeclaration(requiresEOF: false))
                continue
            }

            throw ParseError(
                "Expected top-level state, extension, enum, protocol, macro, or declaration.")
        }

        try consume(.eof)
        try validateBuilderDeclarations(in: constructs)

        if let mainBlock,
            topLevelStates.isEmpty, topLevelCallables.isEmpty, enumerations.isEmpty,
            protocols.isEmpty,
            constructs.isEmpty,
            macros.isEmpty,
            extensions.isEmpty
        {
            return .mainBlock(mainBlock)
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            constructs.count == 1,
            macros.isEmpty,
            extensions.isEmpty
        {
            return .construct(constructs[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            protocols.isEmpty,
            macros.isEmpty,
            enumerations.count == 1, extensions.isEmpty
        {
            return .enumeration(enumerations[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            enumerations.isEmpty,
            protocols.count == 1,
            macros.isEmpty,
            extensions.isEmpty
        {
            return .protocolDefinition(protocols[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            macros.count == 1,
            extensions.isEmpty
        {
            return .macro(macros[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            macros.isEmpty,
            !extensions.isEmpty
        {
            return .extensions(extensions)
        }

        return .module(
            ModuleFileNode(
                mainBlock: mainBlock,
                states: topLevelStates,
                callables: topLevelCallables,
                constructs: constructs,
                enumerations: enumerations,
                protocols: protocols,
                macros: macros,
                extensions: extensions
            )
        )
    }

}
