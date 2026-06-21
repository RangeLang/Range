import Foundation

extension Parser {
    func isExtensionDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        return peek(offset: offset) == .keyword(RangeSyntax.Keyword.typeExtension.rawValue)
    }

    mutating func parseExtensionDeclaration() throws -> ExtensionDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.typeExtension)
        let target = try parseExtensionTarget()
        let conformances = try parseConformanceListIfPresent()
        let initializers: [InitializerDeclaration] = []
        let callables: [CallableDeclaration] = []
        let constructs: [ConstructDeclaration] = []
        let enumerations: [EnumDeclaration] = []
        let enumCases: [EnumCaseDeclaration] = []
        if peek() == .leftBrace {
            try consume(.leftBrace)
            try skipUnknownBlockBody()
            try consume(.rightBrace)
        }
        try validateInitializerDeclarations(initializers, availableDeriveds: [])
        return ExtensionDeclaration(
            macros: macros,
            targetType: target.type,
            genericArgumentConstraints: target.genericArgumentConstraints,
            conformances: conformances,
            initializers: initializers,
            callables: callables,
            constructs: constructs,
            enumerations: enumerations,
            enumCases: enumCases
        )
    }

    mutating func parseExtensionDeclarationForDeclarationDiscovery() throws -> ExtensionDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.typeExtension)
        let target = try parseExtensionTarget()
        let conformances = try parseConformanceListIfPresent()
        var initializers: [InitializerDeclaration] = []
        var callables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var enumCases: [EnumCaseDeclaration] = []
        if peek() == .leftBrace {
            try consume(.leftBrace)
            while peek() != .rightBrace {
                if isCallableStart() {
                    callables.append(try parseCallableDeclaration(signatureOnly: true))
                    continue
                }
                if isInitializerDeclarationStart() {
                    initializers.append(try parseInitializerDeclaration(signatureOnly: true))
                    continue
                }
                if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                    constructs.append(try parseConstructDeclarationForDeclarationDiscovery())
                    continue
                }
                if isEnumDeclarationStart() {
                    enumerations.append(try parseEnumDeclaration(requiresEOF: false))
                    continue
                }
                if isCaseDeclarationStart() {
                    enumCases.append(contentsOf: try parseEnumCaseLine())
                    continue
                }
                advance()
            }
            try consume(.rightBrace)
        }
        return ExtensionDeclaration(
            macros: macros,
            targetType: target.type,
            genericArgumentConstraints: target.genericArgumentConstraints,
            conformances: conformances,
            initializers: initializers,
            callables: callables,
            constructs: constructs,
            enumerations: enumerations,
            enumCases: enumCases
        )
    }

    mutating func parseExtensionTarget() throws -> (
        type: TypeReference, genericArgumentConstraints: [ExtensionGenericArgumentConstraint]
    ) {
        if peek() == .leftBracket || peek() == .leftParen {
            let typeReference = try parseTypeReferenceNode()
            throw ParseError(
                "Extension target must be a nominal type reference, got \(typeReference.displayName)."
            )
        }

        var base: TypeReference = .named(try consumeTypeName())
        while peek() == .dot {
            try consume(.dot)
            base = .member(base: base, name: try consumeTypeName())
        }

        guard peek() == .less else {
            return (base, [])
        }

        try consume(.less)
        var arguments: [TypeReference] = []
        var constraints: [ExtensionGenericArgumentConstraint] = []
        while true {
            if case .identifier(let name) = peek(), peek(offset: 1) == .colon {
                advance()
                try consume(.colon)
                let constraint = try parseTypeReferenceNode()
                arguments.append(.named(name))
                constraints.append(
                    ExtensionGenericArgumentConstraint(parameterName: name, constraint: constraint)
                )
            } else {
                arguments.append(try parseTypeReferenceNode())
            }

            guard peek() == .comma else {
                break
            }
            advance()
        }
        try consume(.greater)
        return (.generic(base: base, arguments: arguments), constraints)
    }
}
