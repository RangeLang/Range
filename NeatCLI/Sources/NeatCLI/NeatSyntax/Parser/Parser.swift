import Foundation

struct Parser {
    struct Invocation {
        let name: String
        let arguments: [InvocationArgument]
        let block: InvocationBlock?
    }

    enum InvocationArgument {
        case string(String)
        case integer(Int)
        case double(Double)
        case percentage(Double)
        case identifier(String)
        case enumCase(String)
    }

    enum InvocationBlock {
        case views([ViewNode])
        case statements([Statement])
    }

    let tokens: [Token]
    var index: Int = 0
    var currentStateNames: Set<String> = []
    var currentStateTypes: [String: BuiltinType] = [:]

    init(source: String) throws {
        let normalized = source.replacingOccurrences(of: "#print(", with: "print(")
        var lexer = Lexer(source: normalized)
        self.tokens = try lexer.tokenize()
    }

    mutating func parseComponent() throws -> ComponentNode {
        let declaration = try parseDeclaration()
        guard declaration.kind != .app else {
            throw ParseError("Expected a renderable declaration, not @main.")
        }
        guard let body = declaration.body else {
            throw ParseError("Component declaration requires a body block.")
        }
        return ComponentNode(
            kind: declaration.kind,
            attribute: declaration.attribute,
            objects: declaration.objects,
            name: declaration.name,
            conformances: declaration.conformances,
            states: declaration.states,
            initializers: declaration.initializers,
            body: body
        )
    }
}
