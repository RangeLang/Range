import Foundation

extension Parser {
    func isEnumDeclarationStart() -> Bool {
        switch peek() {
        case .keyword(NeatSyntax.Keyword.enumeration.rawValue):
            return true
        case .keyword(NeatSyntax.Keyword.primitive.rawValue):
            return peek(offset: 1) == .keyword(NeatSyntax.Keyword.enumeration.rawValue)
        case .atAttribute:
            return peek(offset: 1) == .keyword(NeatSyntax.Keyword.enumeration.rawValue)
                || (peek(offset: 1) == .keyword(NeatSyntax.Keyword.primitive.rawValue)
                    && peek(offset: 2) == .keyword(NeatSyntax.Keyword.enumeration.rawValue))
        default:
            return false
        }
    }

    public mutating func parseEnumDeclaration(requiresEOF: Bool = true) throws
        -> EnumDeclaration
    {
        let modifiers = parseTypeDefinitionModifiers(before: .enumeration)

        try consumeKeyword(.enumeration)
        let name = try consumeTypeName()
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
            attribute: modifiers.attribute,
            primitive: modifiers.primitive,
            name: name,
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
        peek() == .keyword(NeatSyntax.Keyword.caseBranch.rawValue)
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
                let typeName = try consumeTypeName()
                associatedValues.append(
                    AssociatedValueDeclaration(label: firstIdentifier, typeName: typeName)
                )
            } else {
                associatedValues.append(
                    AssociatedValueDeclaration(label: nil, typeName: firstIdentifier)
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
