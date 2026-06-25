import Foundation

extension Parser {
    func isMacroDeclarationStart() -> Bool {
        let offset = macroApplicationLookaheadLength(excluding: ["macro"])
        return isMacroPrefixDeclarationStart(at: 0)
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
        throw ParseError("Expected @macro declaration.")
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
        if bootstrap.parameters.contains(where: { $0.localName == "result" }),
            !arguments.contains(where: { $0.label == "result" })
        {
            arguments.append(CallArgument(label: "result", value: .string("")))
        }
        if bootstrap.parameters.contains(where: { $0.localName == "target" }),
            !arguments.contains(where: { $0.label == "target" })
        {
            arguments.append(CallArgument(label: "target", value: .string("")))
        }
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
        let targetName = try optionalStringMacroDeclarationField(
            "target",
            in: argumentBindings,
            declarationName: "@macro"
        )
        let target = try macroDeclarationTarget(
            explicitTargetName: targetName,
            attachedMacros: attachedMacros
        )
        let expansionType: TypeReference?
        if let resultName {
            expansionType = try parseMacroMemberTypeReference(resultName)
        } else {
            expansionType = nil
        }
        let bindings: MacroBindings?
        let body: [Statement]
        let syntaxBody: EmittedCodeBlock?
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
            syntaxBody = nil
        } else {
            let parsedBody = try parseHostedMacroBody()
            bindings = parsedBody.bindings
            body = parsedBody.body
            syntaxBody = parsedBody.syntaxBody
            parameters = parsedBody.parameters
            genericParameters = parsedBody.genericParameters
        }

        return MacroDeclaration(
            macros: attachedMacros,
            name: macroName,
            genericParameters: genericParameters,
            parameters: parameters,
            target: target,
            expansionType: expansionType,
            bindings: bindings,
            body: body,
            syntaxBody: syntaxBody
        )
    }

    private mutating func parseHostedMacroBody() throws
        -> (
            bindings: MacroBindings?,
            body: [Statement],
            syntaxBody: EmittedCodeBlock?,
            parameters: [RangeFunctionParameter],
            genericParameters: [GenericParameter]
        )
    {
        try consume(.leftBrace)
        let genericParameters = try parseMacroMemberGenerics()
        let parameters = try parseMacroMemberParameters()

        if macroBodyStartsWithBindings() {
            let parsedBindings = try parseMacroBodyBindings()
            let body = try parseFreestandingMacroValueBody(
                parameters: parameters,
                bindings: parsedBindings
            )
            return (parsedBindings, body, nil, parameters, genericParameters)
        }

        if macroBodyStartsWithMacroStatement() {
            let body = try parseFreestandingMacroValueBody(
                parameters: parameters,
                bindings: nil
            )
            return (nil, body, nil, parameters, genericParameters)
        }

        let syntaxBody = try parseEmittedCodeBlock()
        return (nil, [], syntaxBody, parameters, genericParameters)
    }

    private mutating func parseHostedMacroValueBody(
        declaredParameters: [RangeFunctionParameter] = [],
        declaredGenericParameters: [GenericParameter] = []
    ) throws
        -> (
            bindings: MacroBindings?,
            body: [Statement],
            parameters: [RangeFunctionParameter],
            genericParameters: [GenericParameter]
        )
    {
        try consume(.leftBrace)
        let genericParameters = declaredGenericParameters + (try parseMacroMemberGenerics())
        let parameters = declaredParameters + (try parseMacroMemberParameters())
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

    private func macroDeclarationTarget(
        explicitTargetName: String?,
        attachedMacros: [MacroApplication]
    ) throws -> MacroTarget? {
        let attachedTarget = attachedMacroTarget(from: attachedMacros)
        guard let explicitTargetName else {
            return attachedTarget
        }
        let explicitTarget = try macroDeclarationTarget(from: explicitTargetName)
        guard let attachedTarget else {
            return explicitTarget
        }
        return .allOf([attachedTarget, explicitTarget])
    }

    private func macroDeclarationTarget(from name: String) throws -> MacroTarget {
        let names = name.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if names.count > 1 {
            return .anyOf(try names.map(macroDeclarationTarget))
        }

        switch name {
        case "@block", "@syntax", "@statement", "@member", "@property", "@macro":
            return .macroSurface(String(name.dropFirst()))
        case "@construct":
            return .syntax(.named("Construct"))
        case "@extension":
            return .syntax(.named("Extension"))
        case "@enum":
            return .syntax(.named("Enum"))
        case "@function":
            return .syntax(.named("Function"))
        case "@init":
            return .syntax(.named("Init"))
        case "@parameter":
            return .syntax(.named("Parameter"))
        case "@let":
            return .syntax(.named("Let"))
        case "@state":
            return .syntax(.named("State"))
        case "@expression":
            return .syntax(.named("Expression"))
        default:
            throw ParseError("@macro target \(name) is not supported.")
        }
    }

    private func attachedMacroTarget(from macros: [MacroApplication]) -> MacroTarget? {
        let targets = macros.compactMap(attachedMacroTarget)
        guard !targets.isEmpty else {
            return nil
        }
        return targets.count == 1 ? targets[0] : .anyOf(targets)
    }

    private func attachedMacroTarget(from macro: MacroApplication) -> MacroTarget? {
        switch macro.name {
        case "block", "syntax", "statement", "member", "property", "macro":
            return .macroSurface(macro.name)
        case "construct":
            return .syntax(attachedMacroTargetType("Construct", genericArguments: macro.genericArguments))
        case "extension":
            return .syntax(attachedMacroTargetType("Extension", genericArguments: macro.genericArguments))
        case "enum":
            return .syntax(attachedMacroTargetType("Enum", genericArguments: macro.genericArguments))
        case "function":
            return .syntax(attachedMacroTargetType("Function", genericArguments: macro.genericArguments))
        case "init":
            return .syntax(attachedMacroTargetType("Init", genericArguments: macro.genericArguments))
        case "parameter":
            return .syntax(attachedMacroTargetType("Parameter", genericArguments: macro.genericArguments))
        case "let":
            return .syntax(attachedMacroTargetType("Let", genericArguments: macro.genericArguments))
        case "state":
            return .syntax(attachedMacroTargetType("State", genericArguments: macro.genericArguments))
        case "expression":
            return .syntax(attachedMacroTargetType("Expression", genericArguments: macro.genericArguments))
        default:
            return nil
        }
    }

    private func attachedMacroTargetType(
        _ name: String,
        genericArguments: [TypeReference]
    ) -> TypeReference {
        guard !genericArguments.isEmpty else {
            return .named(name)
        }
        return .generic(base: .named(name), arguments: genericArguments)
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
