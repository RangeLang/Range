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

    mutating func parseTargetExpandStatement(targetPath: String) throws -> Statement {
        let components = targetPath.split(separator: ".").map(String.init)
        for (index, component) in components.enumerated() {
            if index > 0 {
                try consume(.dot)
            }
            try consumeIdentifierOrKeyword(component)
        }
        try consume(.dot)
        try consumeIdentifierOrKeyword("expand")
        try consume(.leftBrace)
        let emitted = try parseEmittedCodeBlock()
        return .expand(targetPath: targetPath, block: emitted)
    }

    private mutating func consumeIdentifierOrKeyword(_ expected: String) throws {
        switch peek() {
        case .identifier(let value) where value == expected:
            advance()
        case .keyword(let value) where value == expected:
            advance()
        default:
            throw ParseError("Expected \(expected).")
        }
    }

    mutating func parseEmittedCodeBlock() throws -> EmittedCodeBlock {
        var parts: [EmittedCodePart] = []
        var currentTextTokens: [String] = []
        var emittedTokens: [Token] = []
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
                throw ParseError("Unterminated expand block.")
            case .rightBrace:
                if braceDepth == 1 {
                    flushText()
                    try consume(.rightBrace)
                    braceDepth = 0
                    break
                }
                braceDepth -= 1
                let consumed = advance()
                emittedTokens.append(consumed)
                currentTextTokens.append(renderMacroToken(consumed))
            case .leftBrace:
                braceDepth += 1
                let consumed = advance()
                emittedTokens.append(consumed)
                currentTextTokens.append(renderMacroToken(consumed))
            case .hash where peek(offset: 1) == .leftParen:
                flushText()
                try consume(.hash)
                try consume(.leftParen)
                let expression = try parseExpression(terminatingAt: [.rightParen])
                try consume(.rightParen)
                parts.append(
                    .splice(
                        expression: expression,
                        expected: emittedSpliceExpectedKind(
                            before: emittedTokens,
                            after: peek()
                        )
                    )
                )
            default:
                let consumed = advance()
                emittedTokens.append(consumed)
                currentTextTokens.append(renderMacroToken(consumed))
            }
        }

        return EmittedCodeBlock(parts: parts)
    }

    func emittedSpliceExpectedKind(before tokens: [Token], after nextToken: Token) -> EmittedSyntaxKind {
        let significantTokens = tokens.filter {
            switch $0 {
            case .eof:
                return false
            default:
                return true
            }
        }

        guard let previous = significantTokens.last else {
            return .expression
        }

        switch previous {
        case .keyword(NeatSyntax.Keyword.construct.rawValue),
            .keyword(NeatSyntax.Keyword.enumeration.rawValue),
            .keyword(NeatSyntax.Keyword.protocolDefinition.rawValue),
            .keyword(NeatSyntax.Keyword.namespace.rawValue),
            .keyword(NeatSyntax.Keyword.caseBranch.rawValue):
            return .declaration
        case .keyword(NeatSyntax.Keyword.typeExtension.rawValue):
            return .nominalTypeReference
        case .keyword(NeatSyntax.Keyword.function.rawValue):
            return .callableName
        case .keyword(NeatSyntax.Keyword.binding.rawValue):
            return .typeReference
        case .arrow:
            return .typeReference
        case .less where nextToken == .greater || nextToken == .comma:
            return .typeReference
        case .colon where nextToken == .leftBrace || nextToken == .comma:
            return .nominalTypeReference
        case .colon:
            return .typeReference
        case .comma where nextToken == .leftBrace || nextToken == .comma:
            return .nominalTypeReference
        case .comma where nextToken == .rightParen || nextToken == .greater:
            return .typeReference
        case .leftParen where nextToken == .rightParen || nextToken == .comma:
            return .typeReference
        default:
            if nextToken == .keyword(NeatSyntax.Keyword.function.rawValue) {
                return .nominalTypeReference
            }
            return .expression
        }
    }
}
