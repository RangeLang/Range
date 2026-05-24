import Foundation

public enum TokenDelimiterRole: String, Sendable {
    case prefix
    case postfix
    case infix
}

public struct TokenDelimiterConcept: Equatable, Sendable {
    public let token: String
    public let role: TokenDelimiterRole
    public let pairedToken: String?

    public init(token: String, role: TokenDelimiterRole, pairedToken: String?) {
        self.token = token
        self.role = role
        self.pairedToken = pairedToken
    }
}

public struct TokenMetadataConcept: Equatable, Sendable {
    public let token: String
    public let pattern: String
    public let delimiter: TokenDelimiterConcept?

    public init(token: String, pattern: String, delimiter: TokenDelimiterConcept?) {
        self.token = token
        self.pattern = pattern
        self.delimiter = delimiter
    }
}

public enum LexerTokenOption: String, Sendable {
    case emit
    case skip
    case diagnostic
}

public struct LexerTokenConcept: Equatable, Sendable {
    public let token: String
    public let pattern: String
    public let option: LexerTokenOption
    public let delimiter: TokenDelimiterConcept?

    public init(
        token: String,
        pattern: String,
        option: LexerTokenOption,
        delimiter: TokenDelimiterConcept?
    ) {
        self.token = token
        self.pattern = pattern
        self.option = option
        self.delimiter = delimiter
    }
}

extension DeclarationGraph {
    public var tokenMetadataConcepts: [TokenMetadataConcept] {
        Self.collectTokenMetadataConcepts(from: constructsByName)
    }

    public var tokenDelimiterConcepts: [TokenDelimiterConcept] {
        tokenMetadataConcepts.compactMap(\.delimiter)
    }

    public var lexerTokenConcepts: [LexerTokenConcept] {
        Self.collectLexerTokenConcepts(from: constructsByName)
    }

    static func collectTokenMetadataConcepts(
        from constructsByName: [String: ConstructDeclaration]
    ) -> [TokenMetadataConcept] {
        let tokenNames = Set(
            constructsByName.values.compactMap { declaration in
                declaration.macros.contains(where: { $0.name == "Token" }) ? declaration.name : nil
            }
        )

        return constructsByName.values.compactMap { tokenDeclaration in
            guard tokenNames.contains(tokenDeclaration.name),
                let tokenApplication = tokenDeclaration.macros.first(where: { $0.name == "Token" }),
                let pattern = tokenPattern(from: tokenApplication)
            else {
                return nil
            }

            let delimiter = tokenDeclaration.macros.compactMap { application -> TokenDelimiterConcept? in
                guard application.name == "Delimiter",
                    let role = delimiterRole(from: application)
                else {
                    return nil
                }

                let pairedToken = delimiterPairedTokenName(from: application)
                if let pairedToken, !tokenNames.contains(pairedToken) {
                    return nil
                }

                return TokenDelimiterConcept(
                    token: tokenDeclaration.name,
                    role: role,
                    pairedToken: pairedToken
                )
            }.first

            return TokenMetadataConcept(
                token: tokenDeclaration.name,
                pattern: pattern,
                delimiter: delimiter
            )
        }
        .sorted {
            return $0.token < $1.token
        }
    }

    static func collectLexerTokenConcepts(
        from constructsByName: [String: ConstructDeclaration]
    ) -> [LexerTokenConcept] {
        collectTokenMetadataConcepts(from: constructsByName).compactMap { token in
            guard let tokenDeclaration = constructsByName[token.token],
                let lexerApplication = tokenDeclaration.macros.first(where: { $0.name == "lexer" }),
                let option = lexerOption(from: lexerApplication)
            else {
                return nil
            }

            return LexerTokenConcept(
                token: token.token,
                pattern: token.pattern,
                option: option,
                delimiter: token.delimiter
            )
        }
        .sorted {
            return $0.token < $1.token
        }
    }

    private static func tokenPattern(from application: MacroApplication) -> String? {
        guard let argumentClause = application.argumentClause?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !argumentClause.isEmpty else {
            return nil
        }

        do {
            var parser = try Parser(source: "token(\(argumentClause))")
            _ = try parser.consumeCallableName()
            let arguments = try parser.parseInvocationArgumentsIfPresent()
            try parser.consume(.eof)

            guard arguments.count == 1,
                arguments[0].label == nil,
                case .string(let pattern) = arguments[0].value
            else {
                return nil
            }

            return pattern
        } catch {
            return nil
        }
    }

    private static func delimiterRole(from application: MacroApplication) -> TokenDelimiterRole? {
        guard application.genericArguments.count == 1 else {
            return nil
        }

        let roleName = application.genericArguments[0].displayName
        let normalized = roleName.hasPrefix(".") ? String(roleName.dropFirst()) : roleName
        return TokenDelimiterRole(rawValue: normalized)
    }

    private static func delimiterPairedTokenName(from application: MacroApplication) -> String? {
        guard let argumentClause = application.argumentClause?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !argumentClause.isEmpty else {
            return nil
        }

        do {
            var parser = try Parser(source: "delimiter(\(argumentClause))")
            _ = try parser.consumeCallableName()
            let arguments = try parser.parseInvocationArgumentsIfPresent()
            try parser.consume(.eof)

            guard arguments.count == 1,
                arguments[0].label == nil,
                case .identifier(let name) = arguments[0].value
            else {
                return nil
            }

            return name
        } catch {
            return nil
        }
    }

    private static func lexerOption(from application: MacroApplication) -> LexerTokenOption? {
        guard application.genericArguments.count == 1 else {
            return nil
        }

        let optionName = application.genericArguments[0].displayName
        let normalized = optionName.hasPrefix(".") ? String(optionName.dropFirst()) : optionName
        return LexerTokenOption(rawValue: normalized)
    }
}
