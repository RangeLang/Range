import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.macro.rawValue)
    }

    mutating func parseMacroDeclaration() throws -> MacroDeclaration {
        try consumeKeyword(.macro)

        let name = try consumeCallableName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        let parameters =
            peek() == .leftParen ? try parseFunctionParameters(allowSyntaxCapture: true) : []

        try consume(.colon)
        let target = try parseMacroTarget()
        let (bindings, body) = try parseMacroBody()

        return MacroDeclaration(
            name: name,
            genericParameters: genericParameters,
            parameters: parameters,
            target: target,
            bindings: bindings,
            body: body
        )
    }

    mutating func parseMacroTarget() throws -> MacroTarget {
        let wrapper = try consumeIdentifier()
        try consume(.less)
        let wrappedType = try parseTypeReferenceNode()
        try consume(.greater)

        switch wrapper {
        case "Attached":
            return .attached(wrappedType)
        case "Freestanding":
            return .freestanding(wrappedType)
        default:
            throw ParseError("Expected macro target wrapper Attached<...> or Freestanding<...>.")
        }
    }

    mutating func parseMacroBody() throws -> (bindings: MacroBindings, body: [Statement]) {
        try consume(.leftBrace)

        let targetBinding = try consumeIdentifier()
        try consume(.comma)
        let diagnosticsBinding = try consumeIdentifier()
        try consumeKeyword(.inKeyword)

        let bindings = MacroBindings(
            target: targetBinding,
            diagnostics: diagnosticsBinding
        )

        var localBindings: [String: LocalBindingSymbol] = [
            targetBinding: .init(kind: .constant, type: .named("MacroTarget")),
            diagnosticsBinding: .init(kind: .constant, type: .named("MacroDiagnostics")),
        ]
        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        try consume(.rightBrace)
        return (bindings, statements)
    }

    mutating func parseGenericParameterClauseIfPresent() throws -> [String] {
        guard peek() == .less else {
            return []
        }

        try consume(.less)
        var parameters: [String] = [try consumeIdentifier()]
        while peek() == .comma {
            advance()
            parameters.append(try consumeIdentifier())
        }
        try consume(.greater)
        return parameters
    }
}
