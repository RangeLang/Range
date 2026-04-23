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

        var declarations: [EmittedDeclaration] = []
        while peek() != .rightBrace {
            declarations.append(try parseEmittedDeclaration())
        }

        try consume(.rightBrace)
        return .expand(declarations)
    }

    mutating func parseEmittedDeclaration() throws -> EmittedDeclaration {
        if isEmittedExtensionDeclarationStart() {
            return .extensionDeclaration(try parseEmittedExtensionDeclaration())
        }
        if isStateDeclarationStart() {
            return .stateDeclaration(try parseState())
        }
        if isCallableStart() {
            return .callableDeclaration(try parseCallableDeclaration())
        }
        if isNamespaceDeclarationStart() {
            return .namespaceDeclaration(try parseNamespaceDeclaration(requiresEOF: false))
        }
        if isEnumDeclarationStart() {
            return .enumDeclaration(try parseEnumDeclaration(requiresEOF: false))
        }
        if isProtocolDeclarationStart() {
            return .protocolDeclaration(try parseProtocolDeclaration(requiresEOF: false))
        }
        if isConstructDeclarationStart() || isBuilderDeclarationStart() {
            return .constructDeclaration(try parseConstructDeclaration(requiresEOF: false))
        }

        throw ParseError("Expected emitted declaration inside @expand.")
    }

    func isEmittedExtensionDeclarationStart() -> Bool {
        var offset = 0
        while true {
            switch peek(offset: offset) {
            case .hashDirective:
                offset += 1
                if peek(offset: offset) == .less {
                    var depth = 1
                    offset += 1
                    while depth > 0 {
                        switch peek(offset: offset) {
                        case .less:
                            depth += 1
                        case .greater:
                            depth -= 1
                        case .eof:
                            return false
                        default:
                            break
                        }
                        offset += 1
                    }
                }

                if peek(offset: offset) == .leftParen {
                    var depth = 1
                    offset += 1
                    while depth > 0 {
                        switch peek(offset: offset) {
                        case .leftParen:
                            depth += 1
                        case .rightParen:
                            depth -= 1
                        case .eof:
                            return false
                        default:
                            break
                        }
                        offset += 1
                    }
                }
            default:
                return peek(offset: offset) == .keyword(NeatSyntax.Keyword.typeExtension.rawValue)
            }
        }
    }

    mutating func parseEmittedExtensionDeclaration() throws -> EmittedExtensionDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.typeExtension)

        let target: EmittedNominalTypeReference
        if peek() == .hash {
            try consume(.hash)
            try consume(.leftParen)
            target = .splice(try parseExpression(terminatingAt: [.rightParen]))
            try consume(.rightParen)
        } else {
            target = .type(
                try parseNominalTypeReferenceNode(expectedDescription: "Extension target")
            )
        }
        let conformances = try parseConformanceListIfPresent()

        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        if peek() == .leftBrace {
            try consume(.leftBrace)
            while isCallableStart()
                || isConstructDeclarationStart()
                || isBuilderDeclarationStart()
                || isNamespaceDeclarationStart()
            {
                if isCallableStart() {
                    callables.append(try parseCallableDeclaration())
                    continue
                }
                if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                    constructs.append(try parseConstructDeclaration(requiresEOF: false))
                    continue
                }
                namespaces.append(try parseNamespaceDeclaration(requiresEOF: false))
            }
            try consume(.rightBrace)
        }

        return EmittedExtensionDeclaration(
            macros: macros,
            target: target,
            conformances: conformances,
            callables: callables,
            constructs: constructs,
            namespaces: namespaces
        )
    }
}
