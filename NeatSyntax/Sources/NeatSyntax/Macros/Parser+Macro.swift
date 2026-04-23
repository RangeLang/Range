import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.macro.rawValue)
    }

    mutating func parseMacroDeclaration(signatureOnly: Bool = false) throws -> MacroDeclaration {
        try consumeKeyword(.macro)

        let name = try consumeCallableName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        guard peek() == .leftParen else {
            throw ParseError(
                "Macro declarations must declare an explicit parameter clause. Use () for zero-argument macros."
            )
        }
        let parameters = try parseFunctionParameters(allowSyntaxCapture: true)

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
        currentMacroBodyDepth += 1
        defer { currentMacroBodyDepth -= 1 }
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        try consume(.rightBrace)
        return (bindings, statements)
    }

    mutating func parseExpandStatement() throws -> Statement {
        guard case .atAttribute(let name, _) = peek(), name == "expand" else {
            throw ParseError("Expected @expand block.")
        }
        advance()
        try consume(.leftBrace)
        let emitted = try parseEmittedCodeBlock()
        return .expand(emitted)
    }

    mutating func parseEmittedCodeBlock() throws -> EmittedCodeBlock {
        var parts: [EmittedCodePart] = []
        var currentTextTokens: [String] = []
        var braceDepth = 1

        func flushText() {
            guard !currentTextTokens.isEmpty else { return }
            parts.append(.text(currentTextTokens.joined(separator: " ")))
            currentTextTokens.removeAll(keepingCapacity: true)
        }

        while braceDepth > 0 {
            let token = peek()
            switch token {
            case .eof:
                throw ParseError("Unterminated @expand block.")
            case .rightBrace:
                if braceDepth == 1 {
                    flushText()
                    try consume(.rightBrace)
                    braceDepth = 0
                    break
                }
                braceDepth -= 1
                currentTextTokens.append(renderMacroToken(advance()))
            case .leftBrace:
                braceDepth += 1
                currentTextTokens.append(renderMacroToken(advance()))
            case .hash where peek(offset: 1) == .leftParen:
                flushText()
                try consume(.hash)
                try consume(.leftParen)
                let expression = try parseExpression(terminatingAt: [.rightParen])
                try consume(.rightParen)
                parts.append(.splice(expression))
            default:
                currentTextTokens.append(renderMacroToken(advance()))
            }
        }

        return EmittedCodeBlock(parts: parts)
    }
}
