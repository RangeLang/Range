import Foundation

extension Parser {
    mutating func parseBindingDeclaration() throws -> BindingDeclaration {
        let macros = try parseMacroApplicationsIfPresent()
        try consumeKeyword(.binding)
        let name = try parseDeclarationName(expecting: "binding")
        try consume(.colon)
        let typeName = try consumeTypeReference()
        let storage: BindingStorage
        if peek() == .leftBrace {
            let previousBindingNames = currentBindingNames
            currentBindingNames = previousBindingNames.union([name])
            storage = try parseDerivedBindingStorage(name: name, typeName: typeName)
            currentBindingNames = previousBindingNames.union([name])
        } else {
            storage = .plain
        }
        return BindingDeclaration(
            macros: macros,
            name: name,
            typeName: typeName,
            storage: storage
        )
    }

    mutating func parseDerivedBindingStorage(name: String, typeName: String) throws
        -> BindingStorage
    {
        try consume(.leftBrace)

        var getterBody: [Statement]?
        var setterBody: [Statement]?

        while peek() != .rightBrace {
            if peek() == .keyword(RangeSyntax.Keyword.getter.rawValue) {
                guard getterBody == nil else {
                    throw ParseError("binding '\(name)' can only define one get block.")
                }
                try consumeKeyword(.getter)
                getterBody = try parseStatementBlock(baseLocalBindings: [:])
                continue
            }

            if peek() == .keyword(RangeSyntax.Keyword.setter.rawValue) {
                guard setterBody == nil else {
                    throw ParseError("binding '\(name)' can only define one set block.")
                }
                try consumeKeyword(.setter)
                setterBody = try parseStatementBlock(
                    baseLocalBindings: [
                        "newValue": .init(kind: .constant, type: .named(typeName))
                    ]
                )
                continue
            }

            throw ParseError("Derived binding '\(name)' only supports get and set blocks.")
        }

        try consume(.rightBrace)

        guard let getterBody else {
            throw ParseError("Derived binding '\(name)' requires a get block.")
        }
        guard let setterBody else {
            throw ParseError("Derived binding '\(name)' requires a set block.")
        }

        return .derived(get: getterBody, set: setterBody)
    }

    func isBindingDeclarationStart() -> Bool {
        let offset = isMacroApplicationStart() ? macroApplicationLookaheadLength() : 0
        guard peek(offset: offset) == .keyword(RangeSyntax.Keyword.binding.rawValue) else {
            return false
        }
        guard case .identifier = peek(offset: offset + 1) else { return false }
        if peek(offset: offset + 2) == .colon {
            return true
        }
        return {
            guard case .identifier = peek(offset: offset + 2) else { return false }
            return peek(offset: offset + 3) == .colon
        }()
    }
}
