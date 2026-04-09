import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.macro.rawValue)
    }

    mutating func parseMacroDeclaration(signatureOnly: Bool = false) throws -> MacroDeclaration {
        try consumeKeyword(.macro)

        let name = try consumeCallableName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        let parameters =
            peek() == .leftParen ? try parseFunctionParameters(allowSyntaxCapture: true) : []

        try consume(.colon)
        let target = try parseMacroTarget()
        let expansionType: TypeReference?
        if peek() == .arrow {
            try consume(.arrow)
            expansionType = try parseTypeReferenceNode()
        } else {
            expansionType = nil
        }
        let bindings: MacroBindings
        let body: [Statement]
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                let targetBinding = try consumeIdentifier()
                try consume(.comma)
                let diagnosticsBinding = try consumeIdentifier()
                try consumeKeyword(.inKeyword)
                bindings = MacroBindings(
                    target: targetBinding,
                    diagnostics: diagnosticsBinding
                )
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            } else {
                throw ParseError("Expected macro body.")
            }
            body = []
        } else {
            (bindings, body) = try parseMacroBody()
        }

        return MacroDeclaration(
            name: name,
            genericParameters: genericParameters,
            parameters: parameters,
            target: target,
            expansionType: expansionType,
            bindings: bindings,
            body: body
        )
    }

    mutating func parseMacroTarget() throws -> MacroTarget {
        .syntax(try parseTypeReferenceNode())
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
