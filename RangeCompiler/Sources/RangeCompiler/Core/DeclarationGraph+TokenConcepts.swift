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

public enum TokenOperatorFixity: String, Sendable {
    case prefix
    case infix
    case postfix
}

public enum TokenOperatorAssociativity: String, Sendable {
    case none
    case left
    case right
}

public struct TokenOperatorBindingRange: Equatable, Sendable {
    public let lower: Int
    public let upper: Int

    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }
}

public struct TokenOperatorConcept: Equatable, Sendable {
    public let token: String
    public let fixity: TokenOperatorFixity
    public let binding: TokenOperatorBindingRange
    public let step: Int
    public let delta: Int
    public let signage: String
    public let associativity: TokenOperatorAssociativity

    public init(
        token: String,
        fixity: TokenOperatorFixity,
        binding: TokenOperatorBindingRange,
        step: Int,
        delta: Int,
        signage: String,
        associativity: TokenOperatorAssociativity
    ) {
        self.token = token
        self.fixity = fixity
        self.binding = binding
        self.step = step
        self.delta = delta
        self.signage = signage
        self.associativity = associativity
    }
}

public struct TokenMetadataConcept: Equatable, Sendable {
    public let token: String
    public let pattern: String
    public let delimiter: TokenDelimiterConcept?
    public let operatorBinding: TokenOperatorConcept?

    public init(
        token: String,
        pattern: String,
        delimiter: TokenDelimiterConcept?,
        operatorBinding: TokenOperatorConcept?
    ) {
        self.token = token
        self.pattern = pattern
        self.delimiter = delimiter
        self.operatorBinding = operatorBinding
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
    public let operatorBinding: TokenOperatorConcept?

    public init(
        token: String,
        pattern: String,
        option: LexerTokenOption,
        delimiter: TokenDelimiterConcept?,
        operatorBinding: TokenOperatorConcept? = nil
    ) {
        self.token = token
        self.pattern = pattern
        self.option = option
        self.delimiter = delimiter
        self.operatorBinding = operatorBinding
    }
}

public typealias LexerRepresentationConcept = LexerTokenConcept

extension DeclarationGraph {
    public var tokenMetadataConcepts: [TokenMetadataConcept] {
        Self.collectTokenMetadataConcepts(from: constructsByName)
    }

    public var tokenDelimiterConcepts: [TokenDelimiterConcept] {
        tokenMetadataConcepts.compactMap(\.delimiter)
    }

    public var tokenOperatorConcepts: [TokenOperatorConcept] {
        tokenMetadataConcepts.compactMap(\.operatorBinding)
    }

    public var lexerTokenConcepts: [LexerTokenConcept] {
        lexerRepresentationConcepts
    }

    public var lexerRepresentationConcepts: [LexerRepresentationConcept] {
        Self.collectLexerRepresentationConcepts(from: constructsByName)
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

            let operatorBinding = tokenDeclaration.macros.compactMap { application -> TokenOperatorConcept? in
                guard application.name == "Operator",
                    let fixity = operatorFixity(from: application),
                    let binding = operatorBindingRange(from: application)
                else {
                    return nil
                }

                return TokenOperatorConcept(
                    token: tokenDeclaration.name,
                    fixity: fixity,
                    binding: binding,
                    step: binding.upper - binding.lower,
                    delta: binding.lower - binding.upper,
                    signage: signage(of: binding.lower - binding.upper),
                    associativity: operatorAssociativity(from: application) ?? .none
                )
            }.first

            return TokenMetadataConcept(
                token: tokenDeclaration.name,
                pattern: pattern,
                delimiter: delimiter,
                operatorBinding: operatorBinding
            )
        }
        .sorted {
            return $0.token < $1.token
        }
    }

    static func collectLexerRepresentationConcepts(
        from constructsByName: [String: ConstructDeclaration]
    ) -> [LexerRepresentationConcept] {
        collectTokenMetadataConcepts(from: constructsByName).compactMap { token in
            guard let tokenDeclaration = constructsByName[token.token],
                let lexerApplication = tokenDeclaration.macros.first(where: { $0.name == "lexer" }),
                let option = lexerOption(from: lexerApplication)
            else {
                return nil
            }

            return LexerRepresentationConcept(
                token: token.token,
                pattern: token.pattern,
                option: option,
                delimiter: token.delimiter,
                operatorBinding: token.operatorBinding
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
                (arguments[0].label == nil || arguments[0].label == "pattern"),
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
                (arguments[0].label == nil || arguments[0].label == "pairedToken"),
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

    private static func operatorFixity(from application: MacroApplication) -> TokenOperatorFixity? {
        guard application.genericArguments.count == 1 else {
            return nil
        }

        let fixityName = application.genericArguments[0].displayName
        let normalized = fixityName.hasPrefix(".") ? String(fixityName.dropFirst()) : fixityName
        return TokenOperatorFixity(rawValue: normalized)
    }

    private static func operatorBindingRange(
        from application: MacroApplication
    ) -> TokenOperatorBindingRange? {
        guard let argumentClause = application.argumentClause else {
            return nil
        }

        let normalized = normalizedMacroArgumentClause(argumentClause)
        guard let binding = macroArgument(named: "binding", in: normalized) else {
            return nil
        }

        if binding.hasPrefix("OperatorBindingRange("), binding.hasSuffix(")") {
            guard let lowerValue = macroArgument(named: "lower", in: binding),
                let upperValue = macroArgument(named: "upper", in: binding),
                let lower = Int(lowerValue),
                let upper = Int(upperValue)
            else {
                return nil
            }
            return TokenOperatorBindingRange(lower: lower, upper: upper)
        } else {
            let bounds = binding.components(separatedBy: "..")
            guard bounds.count == 2,
                let lower = Int(bounds[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                let upper = Int(bounds[1].trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return nil
            }
            return TokenOperatorBindingRange(lower: lower, upper: upper)
        }
    }

    private static func operatorAssociativity(
        from application: MacroApplication
    ) -> TokenOperatorAssociativity? {
        guard let argumentClause = application.argumentClause else {
            return nil
        }

        let normalized = normalizedMacroArgumentClause(argumentClause)
        guard let associativity = macroArgument(named: "associativity", in: normalized) else {
            return nil
        }

        let normalizedAssociativity = associativity.hasPrefix(".")
            ? String(associativity.dropFirst())
            : associativity
        return TokenOperatorAssociativity(rawValue: normalizedAssociativity)
    }

    private static func macroArgument(named name: String, in normalized: String) -> String? {
        guard let valueStart = normalized.range(of: "\(name):")?.upperBound else {
            return nil
        }

        var depth = 0
        var current = valueStart
        while current < normalized.endIndex {
            let character = normalized[current]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 {
                    break
                }
                depth -= 1
            } else if character == "," && depth == 0 {
                break
            }
            current = normalized.index(after: current)
        }

        return String(normalized[valueStart..<current])
    }

    private static func normalizedMacroArgumentClause(_ argumentClause: String) -> String {
        argumentClause
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    private static func signage(of value: Int) -> String {
        if value < 0 {
            return "negative"
        }
        if value > 0 {
            return "positive"
        }
        return "neutral"
    }
}
