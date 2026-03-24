import Foundation

public struct Parser {
    struct Invocation {
        let name: String
        let arguments: [CallArgument]
        let block: InvocationBlock?
    }

    enum InvocationBlock {
        case views([ViewNode])
        case statements([Statement])
    }

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
        var declarations: [DeclarationNode] = []
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

            if NeatSyntax.declarationKind(for: peek()) != nil || isBuilderDeclarationStart() {
                declarations.append(try parseDeclaration(requiresEOF: false))
                continue
            }

            throw ParseError("Expected top-level state, extension, or declaration.")
        }

        try consume(.eof)
        try validateBuilderDeclarations(in: declarations)

        if topLevelStates.isEmpty, topLevelCallables.isEmpty, declarations.count == 1,
            extensions.isEmpty
        {
            return .declaration(declarations[0])
        }

        if topLevelStates.isEmpty, topLevelCallables.isEmpty, declarations.isEmpty,
            !extensions.isEmpty
        {
            return .extensions(extensions)
        }

        return .module(
            ModuleFileNode(
                states: topLevelStates,
                callables: topLevelCallables,
                declarations: declarations,
                extensions: extensions
            )
        )
    }

    public mutating func parseComponent() throws -> ComponentNode {
        let declaration = try parseDeclaration()
        guard let body = declaration.body else {
            throw ParseError("Component declaration requires a body block.")
        }
        return ComponentNode(
            kind: declaration.kind,
            attribute: declaration.attribute,
            objects: declaration.objects,
            name: declaration.name,
            conformances: declaration.conformances,
            projectionTarget: declaration.projectionTarget,
            cases: declaration.cases,
            states: declaration.states,
            environments: declaration.environments,
            bindings: declaration.bindings,
            deriveds: declaration.deriveds,
            members: declaration.members,
            initializers: declaration.initializers,
            callables: declaration.callables,
            body: body
        )
    }
}
