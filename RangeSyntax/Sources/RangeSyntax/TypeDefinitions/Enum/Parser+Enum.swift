import Foundation

extension Parser {
    func isEnumDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        switch peek(offset: offset) {
        case .keyword(RangeSyntax.Keyword.enumeration.rawValue):
            return true
        case .atAttribute:
            return peek(offset: offset + 1) == .keyword(RangeSyntax.Keyword.enumeration.rawValue)
        default:
            return false
        }
    }

    public mutating func parseEnumDeclaration(requiresEOF: Bool = true) throws
        -> EnumDeclaration
    {
        let macros = try parseMacroApplicationsIfPresent()
        let attribute = parseAttributeIfPresent(before: .enumeration)

        try consumeKeyword(.enumeration)
        let name = try consumeTypeName()
        let genericParameters = try parseGenericParameterClauseIfPresent()
        let conformances = try parseConformanceListIfPresent()

        var cases: [EnumCaseDeclaration] = []
        if peek() == .leftBrace {
            try consume(.leftBrace)
            while isCaseDeclarationStart() {
                cases.append(contentsOf: try parseEnumCaseLine())
            }
            try consume(.rightBrace)
        }

        if requiresEOF {
            try consume(.eof)
        }

        return EnumDeclaration(
            macros: macros,
            attribute: attribute,
            name: name,
            genericParameters: genericParameters,
            conformances: conformances,
            cases: cases
        )
    }

    mutating func parseEnumCaseLine() throws -> [EnumCaseDeclaration] {
        try consumeKeyword(.caseBranch)
        var declarations: [EnumCaseDeclaration] = []

        while true {
            let caseName = try consumeEnumCaseName()
            let associatedValues = try parseAssociatedValuesIfPresent()
            declarations.append(
                EnumCaseDeclaration(name: caseName, associatedValues: associatedValues)
            )

            guard peek() == .comma else {
                break
            }
            advance()
        }

        return declarations
    }

    func isCaseDeclarationStart() -> Bool {
        peek() == .keyword(RangeSyntax.Keyword.caseBranch.rawValue)
    }

    mutating func parseAssociatedValuesIfPresent() throws -> [AssociatedValueDeclaration] {
        guard peek() == .leftParen else {
            return []
        }

        try consume(.leftParen)
        var associatedValues: [AssociatedValueDeclaration] = []

        while peek() != .rightParen {
            let firstIdentifier = try consumeIdentifier()

            if peek() == .colon {
                try consume(.colon)
                let typeReference = try parseTypeReferenceNode()
                associatedValues.append(
                    AssociatedValueDeclaration(label: firstIdentifier, typeReference: typeReference)
                )
            } else {
                associatedValues.append(
                    AssociatedValueDeclaration(
                        label: nil,
                        typeReference: .named(firstIdentifier)
                    )
                )
            }

            guard peek() == .comma else {
                break
            }
            advance()
        }

        try consume(.rightParen)
        return associatedValues
    }
}
