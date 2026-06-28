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
        let body: [Statement]
        let parameters: [RangeFunctionParameter]
        let genericParameters: [GenericParameter]
        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                genericParameters = try parseMacroMemberGenerics()
                parameters = try parseMacroMemberParameters()
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            } else {
                throw ParseError("Expected macro body.")
            }
            body = []
        } else {
            let parsedBody = try parseHostedMacroValueBody()
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
            body: body
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
        let target = try macroDeclarationTarget(explicitTargetName: targetName)
        let expansionType: TypeReference?
        if let resultName {
            expansionType = try parseMacroMemberTypeReference(resultName)
        } else {
            expansionType = nil
        }
        let body: [Statement]
        let parameters: [RangeFunctionParameter]
        let genericParameters: [GenericParameter]

        if signatureOnly {
            if peek() == .leftBrace {
                try consume(.leftBrace)
                genericParameters = try parseMacroMemberGenerics()
                parameters = try parseMacroMemberParameters()
                try skipUnknownBlockBody()
                try consume(.rightBrace)
            } else {
                throw ParseError("Expected macro body.")
            }
            body = []
        } else {
            let parsedBody = try parseHostedMacroBody()
            body = parsedBody.body
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
            body: body
        )
    }

    private mutating func parseHostedMacroBody() throws
        -> (
            body: [Statement],
            parameters: [RangeFunctionParameter],
            genericParameters: [GenericParameter]
        )
    {
        try consume(.leftBrace)
        let genericParameters = try parseMacroMemberGenerics()
        let parameters = try parseMacroMemberParameters()

        if macroBodyStartsWithMacroStatement() {
            let body = try parseFreestandingMacroValueBody()
            return (body, parameters, genericParameters)
        }

        throw ParseError("Macro bodies must use explicit Range macro statements.")
    }

    private mutating func parseHostedMacroValueBody(
        declaredParameters: [RangeFunctionParameter] = [],
        declaredGenericParameters: [GenericParameter] = []
    ) throws
        -> (
            body: [Statement],
            parameters: [RangeFunctionParameter],
            genericParameters: [GenericParameter]
        )
    {
        try consume(.leftBrace)
        let genericParameters = declaredGenericParameters + (try parseMacroMemberGenerics())
        let parameters = declaredParameters + (try parseMacroMemberParameters())
        let body = try parseFreestandingMacroValueBody()

        return (body, parameters, genericParameters)
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

    private func macroDeclarationTarget(explicitTargetName: String?) throws -> MacroTarget? {
        guard let explicitTargetName else {
            return nil
        }
        return try macroDeclarationTarget(from: explicitTargetName)
    }

    private func macroDeclarationTarget(from name: String) throws -> MacroTarget {
        let names = name.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if names.count > 1 {
            return .anyOf(try names.map(macroDeclarationTarget))
        }

        guard name.hasPrefix("@"), name.count > 1 else {
            throw ParseError("@macro target \(name) must name a macro surface.")
        }
        return .macroSurface(String(name.dropFirst()))
    }

    mutating func parseFreestandingMacroValueBody() throws -> [Statement] {
        var statements: [Statement] = []
        while peek() != .rightBrace {
            statements.append(try parseStatement())
        }
        try consume(.rightBrace)
        return statements
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
            let statement = try parseStatement()
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
            let statement = try parseStatement()
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
            typeReference: try parseMacroMemberTypeReference(type, generics: valueFields.generics),
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
        let typeReference = try valueFields.type.map {
            try parseMacroMemberTypeReference($0, generics: valueFields.generics)
        }
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
        -> (type: String?, generics: [String], current: String?)
    {
        for statement in body {
            let arguments: [CallArgument]
            let valueBody: [Statement]
            switch statement {
            case .macroApplication(let name, let macroArguments) where name == "value":
                arguments = macroArguments
                valueBody = []
            case .macroInvocation(let name, let clause, let body) where name == "value":
                arguments = try clause.map(MacroExpander.parsedMacroArguments) ?? []
                valueBody = body
            default:
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
            let generics = try valueBody.compactMap(macroMemberGenericName)
            return (type, generics, current)
        }
        return (nil, [], nil)
    }

    private func parseMacroMemberTypeReference(
        _ source: String,
        generics: [String] = []
    ) throws -> TypeReference {
        var parser = try Parser(source: source)
        let base = try parser.parseTypeReferenceNode()
        try parser.consume(.eof)
        guard !generics.isEmpty else {
            return base
        }
        let arguments = try generics.map { try parseMacroMemberTypeReference($0) }
        if case .named("Optional") = base, arguments.count == 1 {
            return .optional(arguments[0])
        }
        if case .named("Array") = base, arguments.count == 1 {
            return .array(arguments[0])
        }
        return .generic(base: base, arguments: arguments)
    }

    private func macroMemberGenericName(from statement: Statement) throws -> String? {
        let arguments: [CallArgument]
        switch statement {
        case .macroApplication(let name, let macroArguments) where name == "generic":
            arguments = macroArguments
        case .macroInvocation(let name, let clause, _) where name == "generic":
            arguments = try clause.map(MacroExpander.parsedMacroArguments) ?? []
        default:
            return nil
        }
        guard let nameArgument = arguments.first(where: { $0.label == "name" }),
            case .string(let name) = nameArgument.value,
            !name.isEmpty
        else {
            throw ParseError("@generic macro members must declare name: String.")
        }
        return name
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
}
