import Foundation

public struct Parser {
    let tokens: [Token]
    var index: Int = 0
    var currentStateNames: Set<String> = []
    var currentMutableStateNames: Set<String> = []
    var currentStateTypes: [String: BuiltinType] = [:]
    var currentEnvironmentTypes: [String: BuiltinType] = [:]
    var currentBindingNames: Set<String> = []
    var currentEnvironmentNames: Set<String> = []
    var currentMutableEnvironmentNames: Set<String> = []

    public init(source: String) throws {
        var lexer = Lexer(source: source)
        self.tokens = try lexer.tokenize()
    }

    public mutating func parseSourceFile() throws -> SourceFileNode {
        if isMainBlockStart() {
            return .mainBlock(try parseMainBlock())
        }

        currentStateTypes = [:]

        var topLevelStates: [StateDeclaration] = []
        var topLevelCallables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var extensions: [TypeExtensionDeclaration] = []

        while peek() != .eof {
            if peek() == .keyword(NeatSyntax.Keyword.typeExtension.rawValue) {
                extensions.append(try parseTypeExtensionDeclaration())
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

            if NeatSyntax.constructKind(for: peek()) != nil || isBuilderDeclarationStart() {
                constructs.append(try parseConstructDeclaration(requiresEOF: false))
                continue
            }

            throw ParseError("Expected top-level state, extension, enum, or declaration.")
        }

        try consume(.eof)
        try validateBuilderDeclarations(in: constructs)

        if topLevelStates.isEmpty, topLevelCallables.isEmpty, enumerations.isEmpty,
            constructs.count == 1,
            extensions.isEmpty
        {
            return .construct(constructs[0])
        }

        if topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            enumerations.count == 1, extensions.isEmpty
        {
            return .enumeration(enumerations[0])
        }

        if topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            enumerations.isEmpty,
            !extensions.isEmpty
        {
            return .extensions(extensions)
        }

        return .module(
            ModuleFileNode(
                states: topLevelStates,
                callables: topLevelCallables,
                constructs: constructs,
                enumerations: enumerations,
                extensions: extensions
            )
        )
    }

}
