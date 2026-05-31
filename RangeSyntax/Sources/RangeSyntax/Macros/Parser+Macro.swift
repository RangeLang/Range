import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        if peek() == .keyword(RangeSyntax.Keyword.macro.rawValue) {
            return true
        }
        if peek() == .keyword(RangeSyntax.Keyword.open.rawValue)
            || peek() == .keyword(RangeSyntax.Keyword.closed.rawValue)
        {
            return peek(offset: 1) == .keyword(RangeSyntax.Keyword.macro.rawValue)
        }
        return false
    }

    mutating func parseMacroDeclaration(signatureOnly: Bool = false) throws -> MacroDeclaration {
        let packageVisibility: PackageVisibility
        if peek() == .keyword(RangeSyntax.Keyword.closed.rawValue) {
            try consumeKeyword(.closed)
            packageVisibility = .closed
        } else if peek() == .keyword(RangeSyntax.Keyword.open.rawValue) {
            try consumeKeyword(.open)
            packageVisibility = .open
        } else {
            packageVisibility = .open
        }
        try consumeKeyword(.macro)

        let name = try consumeCallableName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        guard peek() == .leftParen else {
            throw ParseError(
                "Macro declarations must declare an explicit parameter clause. Use () for zero-argument macros."
            )
        }
        let parameters = try parseFunctionParameters(allowSyntaxCapture: true)

        if peek() == .arrow {
            try consume(.arrow)
            let expansionType = try parseTypeReferenceNode()
            let syntaxBody: EmittedCodeBlock?
            if signatureOnly {
                try consume(.leftBrace)
                try skipUnknownBlockBody()
                try consume(.rightBrace)
                syntaxBody = nil
            } else {
                try consume(.leftBrace)
                syntaxBody = try parseEmittedCodeBlock()
            }
            let body: [Statement]
            if syntaxBody == nil, !signatureOnly {
                body = try parseFreestandingMacroValueBody(parameters: parameters)
            } else {
                body = []
            }
            return MacroDeclaration(
                packageVisibility: packageVisibility,
                name: name,
                genericParameters: genericParameters,
                parameters: parameters,
                target: nil,
                expansionType: expansionType,
                bindings: nil,
                body: body,
                syntaxBody: syntaxBody
            )
        }

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
                bindings = try parseMacroBodyBindings()
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
            packageVisibility: packageVisibility,
            name: name,
            genericParameters: genericParameters,
            parameters: parameters,
            target: target,
            expansionType: expansionType,
            bindings: bindings,
            body: body,
            syntaxBody: nil
        )
    }

    mutating func parseMacroTarget() throws -> MacroTarget {
        try parseMacroTargetList()
    }

    mutating func parseMacroTargetList() throws -> MacroTarget {
        var targets = [try parseMacroTargetUnion()]
        while peek() == .comma {
            advance()
            targets.append(try parseMacroTargetUnion())
        }
        return targets.count == 1 ? targets[0] : .anyOf(targets)
    }

    mutating func parseMacroTargetUnion() throws -> MacroTarget {
        var targets = [try parseMacroTargetIntersection()]
        while peek() == .pipe {
            advance()
            targets.append(try parseMacroTargetIntersection())
        }
        return targets.count == 1 ? targets[0] : .anyOf(targets)
    }

    mutating func parseMacroTargetIntersection() throws -> MacroTarget {
        var targets = [try parseMacroTargetAtom()]
        while peek() == .ampersand {
            advance()
            targets.append(try parseMacroTargetAtom())
        }
        return targets.count == 1 ? targets[0] : .allOf(targets)
    }

    mutating func parseMacroTargetAtom() throws -> MacroTarget {
        if case .macroAttribute(let name, _) = peek() {
            advance()
            return .macroSurface(name)
        }

        return .syntax(try parseTypeReferenceNode())
    }

    mutating func parseFreestandingMacroValueBody(parameters: [RangeFunctionParameter]) throws
        -> [Statement]
    {
        var localBindings = Dictionary(
            uniqueKeysWithValues: parameters.map {
                (
                    $0.localName,
                    LocalBindingSymbol(kind: .constant, type: $0.typeReference ?? .named("Unknown"))
                )
            }
        )
        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }
        try consume(.rightBrace)
        return statements
    }
    mutating func parseMacroBody() throws -> (bindings: MacroBindings, body: [Statement]) {
        try consume(.leftBrace)

        let bindings = try parseMacroBodyBindings()

        var localBindings: [String: LocalBindingSymbol] = [
            bindings.target: .init(kind: .constant, type: .named("MacroTarget")),
            bindings.diagnostics: .init(kind: .constant, type: .named("MacroDiagnostics")),
        ]
        if let graph = bindings.graph {
            localBindings[graph] = .init(kind: .constant, type: .named("GraphContext"))
        }
        var statements: [Statement] = []
        currentMacroBodyDepth += 1
        defer { currentMacroBodyDepth -= 1 }
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        try consume(.rightBrace)
        return (bindings, statements)
    }

    mutating func parseMacroBodyBindings() throws -> MacroBindings {
        let targetBinding = try consumeIdentifier()
        try consume(.comma)
        let secondBinding = try consumeIdentifier()

        if peek() == .keyword(RangeSyntax.Keyword.inKeyword.rawValue) {
            try consumeKeyword(.inKeyword)
            return MacroBindings(
                target: targetBinding,
                diagnostics: secondBinding,
                graph: nil
            )
        }

        try consume(.comma)
        let thirdBinding = try consumeIdentifier()

        if peek() == .keyword(RangeSyntax.Keyword.inKeyword.rawValue) {
            try consumeKeyword(.inKeyword)
            return MacroBindings(
                target: targetBinding,
                diagnostics: secondBinding,
                graph: thirdBinding
            )
        }
        throw ParseError("Macro bodies must bind `target, diagnostics in` or `target, diagnostics, graph in`.")
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
        var currentText = ""
        var previousTextRange: RangeSourceRange?
        var emittedTokens: [Token] = []
        var braceDepth = 1

        func flushText() {
            guard !currentText.isEmpty else { return }
            parts.append(.text(currentText))
            currentText.removeAll(keepingCapacity: true)
            previousTextRange = nil
        }

        func appendTextToken(_ token: Token, range: RangeSourceRange) {
            if !currentText.isEmpty {
                if let previousTextRange,
                    previousTextRange.end.line < range.start.line
                {
                    currentText.append("\n")
                } else {
                    currentText.append(" ")
                }
            }
            currentText.append(renderMacroToken(token))
            previousTextRange = range
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
                let range = tokens[index].range
                let consumed = advance()
                emittedTokens.append(consumed)
                appendTextToken(consumed, range: range)
            case .leftBrace:
                braceDepth += 1
                let range = tokens[index].range
                let consumed = advance()
                emittedTokens.append(consumed)
                appendTextToken(consumed, range: range)
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
            case .hashAttribute(let name):
                flushText()
                advance()
                let arguments = try parseInvocationArgumentsIfPresent()
                parts.append(.syntaxMacroInvocation(name: name, arguments: arguments))
            case .macroAttribute(let name, _) where isMacroApplicationAttribute(name):
                flushText()
                advance()
                let arguments = try parseInvocationArgumentsIfPresent()
                parts.append(.syntaxMacroInvocation(name: name, arguments: arguments))
            default:
                let range = tokens[index].range
                let consumed = advance()
                emittedTokens.append(consumed)
                appendTextToken(consumed, range: range)
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
        case .keyword(RangeSyntax.Keyword.construct.rawValue),
            .keyword(RangeSyntax.Keyword.enumeration.rawValue),
            .keyword(RangeSyntax.Keyword.protocolDefinition.rawValue),
            .keyword(RangeSyntax.Keyword.namespace.rawValue),
            .keyword(RangeSyntax.Keyword.caseBranch.rawValue):
            return .declaration
        case .keyword(RangeSyntax.Keyword.typeExtension.rawValue):
            return .nominalTypeReference
        case .keyword(RangeSyntax.Keyword.function.rawValue):
            return .callableName
        case .keyword(RangeSyntax.Keyword.binding.rawValue):
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
        case .leftBracket where nextToken == .rightBracket:
            return .expressionList
        default:
            return .expression
        }
    }
}
