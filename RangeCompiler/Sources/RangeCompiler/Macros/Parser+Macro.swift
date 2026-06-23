import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        let offset = macroApplicationLookaheadLength(excluding: ["macro"])
        return peek(offset: offset) == .keyword(RangeSyntax.Keyword.macro.rawValue)
            || isMacroPrefixDeclarationStart(at: 0)
            || isMacroPrefixDeclarationStart(at: offset)
    }

    mutating func parseMacroDeclaration(signatureOnly: Bool = false) throws -> MacroDeclaration {
        if isMacroPrefixDeclarationStart(at: 0) {
            return try parseMacroPrefixDeclaration(signatureOnly: signatureOnly)
        }

        let macros = try parseMacroApplicationsIfPresent(excluding: ["macro"])
        if isMacroPrefixDeclarationStart(at: 0) {
            return try parseMacroPrefixDeclaration(
                attachedMacros: macros,
                signatureOnly: signatureOnly
            )
        }
        try consumeKeyword(.macro)

        let name = try consumeCallableName()
        let declaredGenericParameters = try parseGenericParameterClauseIfPresent()
        let declaredParameters: [RangeFunctionParameter]
        if peek() == .leftParen {
            declaredParameters = try parseFunctionParameters(allowSyntaxCapture: true)
        } else {
            declaredParameters = []
        }

        if peek() == .arrow {
            try consume(.arrow)
            let expansionType = try parseTypeReferenceNode()
            let syntaxBody: EmittedCodeBlock?
            let bindings: MacroBindings?
            let body: [Statement]
            let parameters: [RangeFunctionParameter]
            let genericParameters: [GenericParameter]
            if signatureOnly {
                try consume(.leftBrace)
                let memberGenericParameters = try parseMacroMemberGenerics()
                let memberParameters = try parseMacroMemberParameters()
                try skipUnknownBlockBody()
                try consume(.rightBrace)
                syntaxBody = nil
                bindings = nil
                body = []
                parameters = declaredParameters + memberParameters
                genericParameters = declaredGenericParameters + memberGenericParameters
            } else {
                try consume(.leftBrace)
                let memberGenericParameters = try parseMacroMemberGenerics()
                let memberParameters = try parseMacroMemberParameters()
                parameters = declaredParameters + memberParameters
                genericParameters = declaredGenericParameters + memberGenericParameters
                if macroBodyStartsWithBindings() {
                    let parsedBindings = try parseMacroBodyBindings()
                    syntaxBody = nil
                    bindings = parsedBindings
                    body = try parseFreestandingMacroValueBody(
                        parameters: parameters,
                        bindings: parsedBindings
                    )
                } else if macroBodyStartsWithMacroStatement() {
                    syntaxBody = nil
                    bindings = nil
                    body = try parseFreestandingMacroValueBody(
                        parameters: parameters,
                        bindings: nil
                    )
                } else {
                    syntaxBody = try parseEmittedCodeBlock()
                    bindings = nil
                    body = []
                }
            }
            return MacroDeclaration(
                macros: macros,
                name: name,
                genericParameters: genericParameters,
                parameters: parameters,
                target: nil,
                expansionType: expansionType,
                bindings: bindings,
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
        let bindings: MacroBindings?
        let body: [Statement]
        var memberGenericParameters: [GenericParameter] = []
        var memberParameters: [RangeFunctionParameter] = []
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                memberGenericParameters = try parseMacroMemberGenerics()
                memberParameters = try parseMacroMemberParameters()
                bindings = macroBodyStartsWithBindings() ? try parseMacroBodyBindings() : nil
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            } else {
                throw ParseError("Expected macro body.")
            }
            body = []
        } else {
            let parsedBody = try parseMacroBody(declaredParameters: declaredParameters)
            bindings = parsedBody.bindings
            body = parsedBody.body
            let parameters = declaredParameters + parsedBody.parameters
            let genericParameters = declaredGenericParameters + parsedBody.genericParameters
            return MacroDeclaration(
                macros: macros,
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
        let parameters = declaredParameters + memberParameters
        let genericParameters = declaredGenericParameters + memberGenericParameters
        return MacroDeclaration(
            macros: macros,
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

    private func isMacroPrefixDeclarationStart(at offset: Int) -> Bool {
        guard case .macroAttribute(let name, nil) = peek(offset: offset),
            name == "macro"
        else {
            return false
        }
        return peek(offset: offset + 1) == .leftParen || peek(offset: offset + 1) == .arrow
    }

    private mutating func parseMacroPrefixDeclaration(signatureOnly: Bool = false) throws
        -> MacroDeclaration
    {
        try parseMacroPrefixDeclaration(attachedMacros: [], signatureOnly: signatureOnly)
    }

    private mutating func parseMacroPrefixDeclaration(
        attachedMacros: [MacroApplication],
        signatureOnly: Bool = false
    ) throws
        -> MacroDeclaration
    {
        guard case .macroAttribute(let name, nil) = peek(), name == "macro" else {
            throw ParseError("Expected @macro declaration.")
        }
        advance()
        if peek() == .leftParen {
            return try parseHostedMacroDeclaration(
                attachedMacros: attachedMacros,
                signatureOnly: signatureOnly
            )
        }

        try consume(.arrow)
        let expansionType = try parseTypeReferenceNode()
        let bindings: MacroBindings?
        let body: [Statement]
        let parameters: [RangeFunctionParameter]
        let genericParameters: [GenericParameter]
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                genericParameters = try parseMacroMemberGenerics()
                parameters = try parseMacroMemberParameters()
                bindings = macroBodyStartsWithBindings() ? try parseMacroBodyBindings() : nil
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            } else {
                throw ParseError("Expected macro body.")
            }
            body = []
        } else {
            let parsedBody = try parseHostedMacroValueBody()
            bindings = parsedBody.bindings
            body = parsedBody.body
            parameters = parsedBody.parameters
            genericParameters = parsedBody.genericParameters
        }

        return MacroDeclaration(
            macros: attachedMacros,
            name: "macro",
            genericParameters: genericParameters,
            parameters: parameters,
            target: .macroSurface("macro"),
            expansionType: expansionType,
            bindings: bindings,
            body: body,
            syntaxBody: nil
        )
    }

    private mutating func parseHostedMacroDeclaration(
        attachedMacros: [MacroApplication],
        signatureOnly: Bool
    ) throws -> MacroDeclaration {
        guard let bootstrap = macroDeclarationsByName["macro"] else {
            throw ParseError("@macro declarations require the bootstrap @macro declaration.")
        }
        var arguments = try parseInvocationArgumentsIfPresent()
        if bootstrap.parameters.contains(where: { $0.localName == "body" }),
            !arguments.contains(where: { $0.label == "body" })
        {
            arguments.append(CallArgument(label: "body", value: .string("")))
        }
        let argumentBindings = try MacroExpander.expressionMacroArgumentBindings(
            for: bootstrap,
            arguments: arguments
        )
        let macroName = try stringMacroDeclarationField(
            "name",
            in: argumentBindings,
            declarationName: "@macro"
        )
        let resultName = try optionalStringMacroDeclarationField(
            "result",
            in: argumentBindings,
            declarationName: "@macro"
        )
        let expansionType = try resultName.map(parseMacroMemberTypeReference)
        let bindings: MacroBindings?
        let body: [Statement]
        let parameters: [RangeFunctionParameter]
        let genericParameters: [GenericParameter]

        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                genericParameters = try parseMacroMemberGenerics()
                parameters = try parseMacroMemberParameters()
                bindings = macroBodyStartsWithBindings() ? try parseMacroBodyBindings() : nil
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            } else {
                throw ParseError("Expected macro body.")
            }
            body = []
        } else {
            let parsedBody = try parseHostedMacroValueBody()
            bindings = parsedBody.bindings
            body = parsedBody.body
            parameters = parsedBody.parameters
            genericParameters = parsedBody.genericParameters
        }

        return MacroDeclaration(
            macros: attachedMacros,
            name: macroName,
            genericParameters: genericParameters,
            parameters: parameters,
            target: nil,
            expansionType: expansionType,
            bindings: bindings,
            body: body,
            syntaxBody: nil
        )
    }

    private mutating func parseHostedMacroValueBody() throws
        -> (
            bindings: MacroBindings?,
            body: [Statement],
            parameters: [RangeFunctionParameter],
            genericParameters: [GenericParameter]
        )
    {
        try consume(.leftBrace)
        let genericParameters = try parseMacroMemberGenerics()
        let parameters = try parseMacroMemberParameters()
        let bindings: MacroBindings?
        let body: [Statement]

        if macroBodyStartsWithBindings() {
            let parsedBindings = try parseMacroBodyBindings()
            bindings = parsedBindings
            body = try parseFreestandingMacroValueBody(
                parameters: parameters,
                bindings: parsedBindings
            )
        } else {
            bindings = nil
            body = try parseFreestandingMacroValueBody(
                parameters: parameters,
                bindings: nil
            )
        }

        return (bindings, body, parameters, genericParameters)
    }

    private func stringMacroDeclarationField(
        _ name: String,
        in bindings: [String: Expression],
        declarationName: String
    ) throws -> String {
        guard case .string(let value)? = bindings[name] else {
            throw ParseError("\(declarationName) requires \(name): String.")
        }
        return value
    }

    private func optionalStringMacroDeclarationField(
        _ name: String,
        in bindings: [String: Expression],
        declarationName: String
    ) throws -> String? {
        guard let expression = bindings[name] else {
            return nil
        }
        guard case .string(let value) = expression else {
            throw ParseError("\(declarationName) field \(name) must be String.")
        }
        return value.isEmpty ? nil : value
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
        try parseFreestandingMacroValueBody(parameters: parameters, bindings: nil)
    }

    mutating func parseFreestandingMacroValueBody(
        parameters: [RangeFunctionParameter],
        bindings: MacroBindings?
    ) throws -> [Statement] {
        var localBindings = Dictionary(
            uniqueKeysWithValues: parameters.map {
                (
                    $0.localName,
                    LocalBindingSymbol(kind: .constant, type: $0.typeReference ?? .named("Unknown"))
                )
            }
        )
        if let bindings {
            localBindings[bindings.target] = .init(
                kind: .constant,
                type: .member(base: .named("Macro"), name: "Target")
            )
            localBindings[bindings.diagnostics] = .init(
                kind: .constant,
                type: .named("MacroDiagnostics")
            )
            if let graph = bindings.graph {
                localBindings[graph] = .init(kind: .constant, type: .named("GraphContext"))
            }
        }
        var statements: [Statement] = []
        currentMacroBodyDepth += 1
        defer { currentMacroBodyDepth -= 1 }
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }
        try consume(.rightBrace)
        return statements
    }

    private func macroBodyStartsWithBindings() -> Bool {
        switch (peek(), peek(offset: 1), peek(offset: 2)) {
        case (.identifier, .comma, _), (.keyword, .comma, _):
            return true
        default:
            return false
        }
    }

    private func macroBodyStartsWithMacroStatement() -> Bool {
        if case .macroAttribute = peek() {
            return true
        }
        return false
    }

    mutating func parseMacroBody(declaredParameters: [RangeFunctionParameter] = []) throws
        -> (
            bindings: MacroBindings?,
            body: [Statement],
            parameters: [RangeFunctionParameter],
            genericParameters: [GenericParameter]
        )
    {
        try consume(.leftBrace)

        let genericParameters = try parseMacroMemberGenerics()
        let parameters = try parseMacroMemberParameters()
        let bindings = macroBodyStartsWithBindings() ? try parseMacroBodyBindings() : nil

        var localBindings: [String: LocalBindingSymbol] = [:]
        if let bindings {
            localBindings[bindings.target] = .init(
                kind: .constant,
                type: .member(base: .named("Macro"), name: "Target")
            )
            localBindings[bindings.diagnostics] = .init(
                kind: .constant,
                type: .named("MacroDiagnostics")
            )
            if let graph = bindings.graph {
                localBindings[graph] = .init(kind: .constant, type: .named("GraphContext"))
            }
        }
        for parameter in declaredParameters + parameters {
            localBindings[parameter.localName] = .init(
                kind: .constant,
                type: parameter.typeReference ?? .named("Unknown")
            )
        }
        var statements: [Statement] = []
        currentMacroBodyDepth += 1
        defer { currentMacroBodyDepth -= 1 }
        while peek() != .rightBrace {
            statements.append(try parseStatement(localBindings: &localBindings))
        }

        try consume(.rightBrace)
        return (bindings, statements, parameters, genericParameters)
    }

    mutating func parseMacroMemberGenerics() throws -> [GenericParameter] {
        var parameters: [GenericParameter] = []
        while case .macroAttribute(let name, _) = peek(), name == "generic" {
            var localBindings: [String: LocalBindingSymbol] = [:]
            let statement = try parseStatement(localBindings: &localBindings)
            guard let parameter = try macroMemberGeneric(from: statement) else {
                continue
            }
            parameters.append(parameter)
        }
        return parameters
    }

    mutating func parseMacroMemberParameters() throws -> [RangeFunctionParameter] {
        var parameters: [RangeFunctionParameter] = []
        while case .macroAttribute(let name, _) = peek(), name == "parameter" {
            var localBindings: [String: LocalBindingSymbol] = [:]
            let statement = try parseStatement(localBindings: &localBindings)
            guard let parameter = try macroMemberParameter(from: statement) else {
                continue
            }
            parameters.append(parameter)
        }
        return parameters
    }

    private func macroMemberGeneric(from statement: Statement) throws -> GenericParameter? {
        let genericArguments: [CallArgument]
        let body: [Statement]
        switch statement {
        case .macroApplication(let name, let arguments) where name == "generic":
            genericArguments = arguments
            body = []
        case .macroInvocation(let name, let clause, let invocationBody) where name == "generic":
            genericArguments = try clause.map(MacroExpander.parsedMacroArguments) ?? []
            body = invocationBody
        default:
            return nil
        }

        guard let nameArgument = genericArguments.first(where: { $0.label == "name" }),
            case .string(let genericName) = nameArgument.value
        else {
            throw ParseError("@generic macro members must declare name: String.")
        }

        let valueFields = try macroMemberValueFields(in: body)
        guard let type = valueFields.type else {
            return .type(name: genericName, constraint: nil, defaultArgument: nil)
        }

        return .value(
            name: genericName,
            typeReference: try parseMacroMemberTypeReference(type),
            defaultValue: try macroMemberDefaultValue(
                type: valueFields.type,
                current: valueFields.current
            )
        )
    }

    private func macroMemberParameter(from statement: Statement) throws -> RangeFunctionParameter? {
        let parameterArguments: [CallArgument]
        let body: [Statement]
        switch statement {
        case .macroApplication(let name, let arguments) where name == "parameter":
            parameterArguments = arguments
            body = []
        case .macroInvocation(let name, let clause, let invocationBody) where name == "parameter":
            parameterArguments = try clause.map(MacroExpander.parsedMacroArguments) ?? []
            body = invocationBody
        default:
            return nil
        }

        guard let nameArgument = parameterArguments.first(where: { $0.label == "name" }),
            case .string(let parameterName) = nameArgument.value
        else {
            throw ParseError("@parameter macro members must declare name: String.")
        }

        let valueFields = try macroMemberValueFields(in: body)
        let typeReference = try valueFields.type.map(parseMacroMemberTypeReference)
        let defaultValue = try macroMemberDefaultValue(
            type: valueFields.type,
            current: valueFields.current
        )

        return RangeFunctionParameter(
            macros: [],
            name: parameterName,
            typeReference: typeReference,
            defaultValue: defaultValue,
            slotName: nil
        )
    }

    private func macroMemberValueFields(in body: [Statement]) throws
        -> (type: String?, current: String?)
    {
        for statement in body {
            guard case .macroApplication(let name, let arguments) = statement,
                name == "value"
            else {
                continue
            }
            var type: String?
            var current: String?
            for argument in arguments {
                guard let label = argument.label else {
                    continue
                }
                switch (label, argument.value) {
                case ("type", .string(let value)):
                    type = value
                case ("current", .string(let value)):
                    current = value.isEmpty ? nil : value
                default:
                    continue
                }
            }
            return (type, current)
        }
        return (nil, nil)
    }

    private func parseMacroMemberTypeReference(_ source: String) throws -> TypeReference {
        var parser = try Parser(source: source)
        let typeReference = try parser.parseTypeReferenceNode()
        try parser.consume(.eof)
        return typeReference
    }

    private func parseMacroMemberExpression(_ source: String) throws -> Expression {
        var parser = try Parser(source: source)
        let expression = try parser.parseExpression()
        try parser.consume(.eof)
        return expression
    }

    private func macroMemberDefaultValue(type: String?, current: String?) throws -> Expression? {
        guard let current else {
            return nil
        }
        if type == "String", !current.contains("(") {
            return .string(current)
        }
        return try parseMacroMemberExpression(current)
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

    mutating func parseTargetEmittedCodeStatement(
        targetPath: String,
        operation: String
    ) throws -> Statement {
        let components = targetPath.split(separator: ".").map(String.init)
        for (index, component) in components.enumerated() {
            if index > 0 {
                try consume(.dot)
            }
            try consumeIdentifierOrKeyword(component)
        }
        try consume(.dot)
        try consumeIdentifierOrKeyword(operation)
        try consume(.leftBrace)
        let emitted = try parseEmittedCodeBlock()
        if operation == "replace" {
            return .replace(targetPath: targetPath, block: emitted)
        }
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
            .keyword(RangeSyntax.Keyword.caseBranch.rawValue):
            return .declaration
        case .keyword(RangeSyntax.Keyword.typeExtension.rawValue):
            return .nominalTypeReference
        case .keyword(RangeSyntax.Keyword.function.rawValue),
            .keyword(RangeSyntax.Keyword.macro.rawValue):
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
