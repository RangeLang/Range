import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.macro.rawValue)
    }

    func isMarkerDeclarationStart() -> Bool {
        peek() == .keyword(NeatSyntax.Keyword.marker.rawValue)
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
            body: body,
            syntaxBody: nil
        )
    }

    mutating func parseMacroTarget() throws -> MacroTarget {
        .syntax(try parseTypeReferenceNode())
    }

    mutating func parseMarkerDeclaration(signatureOnly: Bool = false) throws -> MarkerDeclaration {
        try consumeKeyword(.marker)

        let name = try consumeCallableName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        guard peek() == .leftParen else {
            throw ParseError(
                "Marker declarations must declare an explicit parameter clause. Use () for zero-argument markers."
            )
        }
        let parameters = try parseFunctionParameters(allowSyntaxCapture: false)

        try consume(.colon)
        let firstType = try parseTypeReferenceNode()
        let target: MacroTarget
        let valueType: TypeReference
        if peek() == .arrow {
            target = .syntax(firstType)
            try consume(.arrow)
            valueType = try parseTypeReferenceNode()
        } else if let namespaceTarget = firstType.namespaceRegistrationTarget {
            target = .syntax(namespaceTarget)
            valueType = firstType
        } else {
            throw ParseError(
                "Marker declarations without `->` must use an effect type such as Namespace<Construct>."
            )
        }
        let globalRegistrations = try parseMarkerGlobalRegistrationsIfPresent()

        let body: [Statement]
        if signatureOnly {
            guard peek() == .leftBrace else {
                body = []
                return MarkerDeclaration(
                    name: name,
                    genericParameters: genericParameters,
                    parameters: parameters,
                    target: target,
                    valueType: valueType,
                    globalRegistrations: globalRegistrations,
                    body: body
                )
            }
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
            body = []
        } else if peek() == .leftBrace {
            body = try parseMarkerBody(parameters: parameters)
        } else {
            body = []
        }

        return MarkerDeclaration(
            name: name,
            genericParameters: genericParameters,
            parameters: parameters,
            target: target,
            valueType: valueType,
            globalRegistrations: globalRegistrations,
            body: body
        )
    }

    mutating func parseMarkerGlobalRegistrationsIfPresent() throws -> [MarkerGlobalRegistration] {
        guard case .identifier("registers") = peek() else {
            return []
        }
        advance()

        var registrations: [MarkerGlobalRegistration] = []
        while true {
            let rawKind: String
            switch peek() {
            case .identifier(let value), .keyword(let value):
                rawKind = value
                advance()
            default:
                throw ParseError("Expected marker global registration kind after 'registers'.")
            }

            guard let registration = MarkerGlobalRegistration(rawValue: rawKind) else {
                throw ParseError("Unknown marker global registration '\(rawKind)'.")
            }
            registrations.append(registration)

            guard peek() == .comma else {
                break
            }
            advance()
        }

        return registrations
    }

    mutating func parseFreestandingMacroValueBody(parameters: [NeatFunctionParameter]) throws
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

    mutating func parseMarkerBody(parameters: [NeatFunctionParameter]) throws -> [Statement] {
        try consume(.leftBrace)
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
            case .hashDirective(let name):
                flushText()
                advance()
                let arguments = try parseInvocationArgumentsIfPresent()
                parts.append(.syntaxMacroInvocation(name: name, arguments: arguments))
            case .atAttribute(let name, _) where isMacroApplicationAttribute(name):
                flushText()
                advance()
                let arguments = try parseInvocationArgumentsIfPresent()
                parts.append(.syntaxMacroInvocation(name: name, arguments: arguments))
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
        case .leftBracket where nextToken == .rightBracket:
            return .expressionList
        default:
            return .expression
        }
    }
}
