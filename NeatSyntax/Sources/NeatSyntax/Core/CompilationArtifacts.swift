import Foundation

public struct CompilationArtifactSnapshot {
    public let path: String
    public let tokens: String
    public let ast: String

    public init(path: String, tokens: String, ast: String) {
        self.path = path
        self.tokens = tokens
        self.ast = ast
    }
}

public struct CompilationArtifactsEmitter {
    public init() {}

    public func snapshot(path: String, source: String) throws -> CompilationArtifactSnapshot {
        CompilationArtifactSnapshot(
            path: path,
            tokens: try renderTokens(source: source),
            ast: try renderAST(source: source)
        )
    }

    public func renderTokens(source: String) throws -> String {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        return renderSection(
            title: "Tokens",
            lines: tokens.map(render)
        )
    }

    public func renderAST(source: String) throws -> String {
        var parser = try Parser(source: source)
        let sourceFile = try parser.parseSourceFile()
        return renderSection(
            title: "AST",
            body: debugDump(sourceFile)
        )
    }

    public func renderGraph(files: [ParsedSourceFile]) -> String {
        DependencyGraphBuilder().build(files: files).render()
    }

    public func renderGraphHTML(files: [ParsedSourceFile], title: String) -> String {
        DependencyGraphBuilder().build(files: files).renderHTML(title: title)
    }

    private func render(_ token: Token) -> String {
        switch token {
        case .identifier(let value):
            return "identifier(\(value))"
        case .hashDirective(let value):
            return "hashDirective(#\(value))"
        case .stringLiteral(let value):
            return "stringLiteral(\(value.debugDescription))"
        case .integer(let value):
            return "integer(\(value))"
        case .double(let value):
            return "double(\(value))"
        case .keyword(let value):
            return "keyword(\(value))"
        case .atAttribute(let name, let argument):
            if let argument {
                return "atAttribute(@\(name)(\(argument)))"
            }
            return "atAttribute(@\(name))"
        case .leftBrace:
            return "leftBrace"
        case .rightBrace:
            return "rightBrace"
        case .leftParen:
            return "leftParen"
        case .rightParen:
            return "rightParen"
        case .leftBracket:
            return "leftBracket"
        case .rightBracket:
            return "rightBracket"
        case .asterisk:
            return "asterisk"
        case .dot:
            return "dot"
        case .ellipsis:
            return "ellipsis"
        case .colon:
            return "colon"
        case .arrow:
            return "arrow"
        case .bang:
            return "bang"
        case .equal:
            return "equal"
        case .equalEqual:
            return "equalEqual"
        case .bangEqual:
            return "bangEqual"
        case .less:
            return "less"
        case .lessEqual:
            return "lessEqual"
        case .greater:
            return "greater"
        case .greaterEqual:
            return "greaterEqual"
        case .plus:
            return "plus"
        case .plusEqual:
            return "plusEqual"
        case .andAnd:
            return "andAnd"
        case .orOr:
            return "orOr"
        case .question:
            return "question"
        case .questionQuestion:
            return "questionQuestion"
        case .dollar:
            return "dollar"
        case .percent:
            return "percent"
        case .comma:
            return "comma"
        case .eof:
            return "eof"
        }
    }

    private func debugDump<T>(_ value: T) -> String {
        var output = ""
        dump(value, to: &output)
        return output
    }

    private func renderSection(title: String, lines: [String]) -> String {
        renderSection(title: title, body: lines.joined(separator: "\n"))
    }

    private func renderSection(title: String, body: String) -> String {
        let indentedBody =
            body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  \($0)" }
            .joined(separator: "\n")

        return """
            \(title):
            \(indentedBody)
            """
    }
}
