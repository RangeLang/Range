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
    var currentBindingNames: Set<String> = []

    public init(source: String) throws {
        var lexer = Lexer(source: source)
        self.tokens = try lexer.tokenize()
    }

    public mutating func parseSourceFile() throws -> SourceFileNode {
        if isMainBlockStart() {
            return .mainBlock(try parseMainBlock())
        }
        return .declaration(try parseDeclaration())
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
            bindings: declaration.bindings,
            members: declaration.members,
            initializers: declaration.initializers,
            callables: declaration.callables,
            body: body
        )
    }
}
