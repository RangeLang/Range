import Foundation

public struct Parser {
    struct OperatorEnvironment {
        var precedenceGroups: [String: PrecedenceGroupDeclaration]
        var infixOperators: [String: OperatorDeclaration]
        var prefixOperators: Set<String>
        var postfixOperators: Set<String>

        static func bootstrap() -> OperatorEnvironment {
            let groups = [
                PrecedenceGroupDeclaration(
                    name: "AssignmentPrecedence",
                    associativity: .right,
                    higherThan: [],
                    lowerThan: [],
                    assignment: true
                ),
                PrecedenceGroupDeclaration(
                    name: "LogicalDisjunctionPrecedence",
                    associativity: .left,
                    higherThan: ["AssignmentPrecedence"],
                    lowerThan: [],
                    assignment: nil
                ),
                PrecedenceGroupDeclaration(
                    name: "LogicalConjunctionPrecedence",
                    associativity: .left,
                    higherThan: ["LogicalDisjunctionPrecedence"],
                    lowerThan: [],
                    assignment: nil
                ),
                PrecedenceGroupDeclaration(
                    name: "ComparisonPrecedence",
                    associativity: OperatorAssociativity.none,
                    higherThan: ["LogicalConjunctionPrecedence"],
                    lowerThan: [],
                    assignment: nil
                ),
                PrecedenceGroupDeclaration(
                    name: "NilCoalescingPrecedence",
                    associativity: .right,
                    higherThan: ["ComparisonPrecedence"],
                    lowerThan: [],
                    assignment: nil
                ),
                PrecedenceGroupDeclaration(
                    name: "AdditionPrecedence",
                    associativity: .left,
                    higherThan: ["NilCoalescingPrecedence"],
                    lowerThan: [],
                    assignment: nil
                ),
                PrecedenceGroupDeclaration(
                    name: "MultiplicationPrecedence",
                    associativity: .left,
                    higherThan: ["AdditionPrecedence"],
                    lowerThan: [],
                    assignment: nil
                ),
            ]

            let operators = [
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "+",
                    precedenceGroup: "AdditionPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "-",
                    precedenceGroup: "AdditionPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "*",
                    precedenceGroup: "MultiplicationPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "/",
                    precedenceGroup: "MultiplicationPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "%",
                    precedenceGroup: "MultiplicationPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "??",
                    precedenceGroup: "NilCoalescingPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "==",
                    precedenceGroup: "ComparisonPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "!=",
                    precedenceGroup: "ComparisonPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "<",
                    precedenceGroup: "ComparisonPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "<=",
                    precedenceGroup: "ComparisonPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: ">",
                    precedenceGroup: "ComparisonPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: ">=",
                    precedenceGroup: "ComparisonPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "&&",
                    precedenceGroup: "LogicalConjunctionPrecedence"
                ),
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "||",
                    precedenceGroup: "LogicalDisjunctionPrecedence"
                ),
            ]

            return OperatorEnvironment(
                precedenceGroups: Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) }),
                infixOperators: Dictionary(uniqueKeysWithValues: operators.map { ($0.symbol, $0) }),
                prefixOperators: ["!"],
                postfixOperators: ["..."]
            )
        }

        mutating func register(precedenceGroup: PrecedenceGroupDeclaration) {
            precedenceGroups[precedenceGroup.name] = precedenceGroup
        }

        mutating func register(operator declaration: OperatorDeclaration) {
            switch declaration.fixity {
            case .infix:
                infixOperators[declaration.symbol] = declaration
            case .prefix:
                prefixOperators.insert(declaration.symbol)
            case .postfix:
                postfixOperators.insert(declaration.symbol)
            }
        }

        func precedence(of groupName: String) -> Int {
            if let group = precedenceGroups[groupName], !group.higherThan.isEmpty {
                return group.higherThan.map { precedence(of: $0) + 1 }.max() ?? 0
            }
            return 0
        }
    }

    let tokens: [Token]
    var index: Int = 0
    var currentStateNames: Set<String> = []
    var currentMutableStateNames: Set<String> = []
    var currentStateTypes: [String: TypeReference] = [:]
    var currentEnvironmentTypes: [String: TypeReference] = [:]
    var currentCallableReturnTypes: [String: TypeReference] = [:]
    var currentBindingNames: Set<String> = []
    var currentEnvironmentNames: Set<String> = []
    var currentMutableEnvironmentNames: Set<String> = []
    var currentSelfAvailable: Bool = false
    var currentExpressionTerminators: [Token] = []
    var operatorEnvironment: OperatorEnvironment
    var literalBridgeResolver: LiteralBridgeResolver
    var declarationMemberResolver: DeclarationMemberResolver
    var declarationOperatorResolver: DeclarationOperatorResolver
    var declarationMacroExpansionResolver: DeclarationMacroExpansionResolver
    var discoveredCallableReturnTypes: [String: TypeReference]
    var macroDeclarationsByName: [String: MacroDeclaration]
    var macroExpansionTypes: [String: TypeReference] = [:]

    public init(
        source: String,
        literalBridgeResolver: LiteralBridgeResolver = .empty,
        declarationMemberResolver: DeclarationMemberResolver = .empty,
        declarationOperatorResolver: DeclarationOperatorResolver = .empty,
        declarationMacroExpansionResolver: DeclarationMacroExpansionResolver = .empty,
        discoveredCallableReturnTypes: [String: TypeReference] = [:],
        macroDeclarationsByName: [String: MacroDeclaration] = [:],
        macroExpansionTypes: [String: TypeReference] = [:]
    ) throws {
        var lexer = Lexer(source: source)
        self.tokens = try lexer.tokenize()
        self.operatorEnvironment = .bootstrap()
        self.literalBridgeResolver = literalBridgeResolver
        self.declarationMemberResolver = declarationMemberResolver
        self.declarationOperatorResolver = declarationOperatorResolver
        self.declarationMacroExpansionResolver = declarationMacroExpansionResolver
        self.discoveredCallableReturnTypes = discoveredCallableReturnTypes
        self.macroDeclarationsByName = macroDeclarationsByName
        self.macroExpansionTypes = macroExpansionTypes
    }

    mutating func registerMacroDeclaration(_ declaration: MacroDeclaration) {
        macroDeclarationsByName[declaration.name] = declaration
        declarationMacroExpansionResolver = DeclarationMacroExpansionResolver(
            macrosByName: macroDeclarationsByName
        )
        if let expansionType = declaration.expansionType {
            macroExpansionTypes[declaration.name] = expansionType
        } else {
            macroExpansionTypes.removeValue(forKey: declaration.name)
        }
    }

    func isCurrentExpressionTerminator(_ token: Token) -> Bool {
        currentExpressionTerminators.contains(where: { $0 == token })
    }

    public mutating func parseSourceFile() throws -> SourceFileNode {
        currentStateTypes = [:]
        currentCallableReturnTypes = discoveredCallableReturnTypes

        var mainBlock: MainBlockNode?
        var topLevelStates: [StateDeclaration] = []
        var topLevelCallables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var enumerations: [EnumDeclaration] = []
        var protocols: [ProtocolDeclaration] = []
        var macros: [MacroDeclaration] = []
        var precedenceGroups: [PrecedenceGroupDeclaration] = []
        var operators: [OperatorDeclaration] = []
        var extensions: [ExtensionDeclaration] = []

        while peek() != .eof {
            if isMainBlockStart() {
                guard mainBlock == nil else {
                    throw ParseError("Only one @main block is allowed per file.")
                }
                mainBlock = try parseMainBlock(requiresEOF: false)
                continue
            }

            if peek() == .keyword(NeatSyntax.Keyword.typeExtension.rawValue) {
                extensions.append(try parseExtensionDeclaration())
                continue
            }

            if isStateDeclarationStart() {
                let state = try parseState()
                topLevelStates.append(state)
                currentStateTypes[state.name] = state.type
                continue
            }

            if isCallableStart() {
                topLevelCallables.append(try parseCallableDeclaration())
                continue
            }

            if isNamespaceDeclarationStart() {
                namespaces.append(try parseNamespaceDeclaration(requiresEOF: false))
                continue
            }

            if isEnumDeclarationStart() {
                enumerations.append(try parseEnumDeclaration(requiresEOF: false))
                continue
            }

            if isProtocolDeclarationStart() {
                protocols.append(try parseProtocolDeclaration(requiresEOF: false))
                continue
            }

            if isMacroDeclarationStart() {
                let declaration = try parseMacroDeclaration()
                macros.append(declaration)
                registerMacroDeclaration(declaration)
                continue
            }

            if isPrecedenceGroupDeclarationStart() {
                let declaration = try parsePrecedenceGroupDeclaration(requiresEOF: false)
                precedenceGroups.append(declaration)
                operatorEnvironment.register(precedenceGroup: declaration)
                continue
            }

            if isOperatorDeclarationStart() {
                let declaration = try parseOperatorDeclaration(requiresEOF: false)
                operators.append(declaration)
                operatorEnvironment.register(operator: declaration)
                continue
            }

            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                constructs.append(try parseConstructDeclaration(requiresEOF: false))
                continue
            }

            throw ParseError(
                "Expected top-level state, extension, enum, protocol, macro, precedencegroup, operator declaration, or declaration."
            )
        }

        try consume(.eof)
        try validateBuilderDeclarations(in: constructs)
        try validateCallableDeclarations(topLevelCallables)

        if let mainBlock,
            topLevelStates.isEmpty, topLevelCallables.isEmpty, enumerations.isEmpty,
            protocols.isEmpty,
            constructs.isEmpty,
            namespaces.isEmpty,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            extensions.isEmpty
        {
            return .mainBlock(mainBlock)
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            constructs.count == 1,
            namespaces.isEmpty,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            extensions.isEmpty
        {
            return .construct(constructs[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            namespaces.isEmpty,
            protocols.isEmpty,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            enumerations.count == 1, extensions.isEmpty
        {
            return .enumeration(enumerations[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            namespaces.isEmpty,
            enumerations.isEmpty,
            protocols.count == 1,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            extensions.isEmpty
        {
            return .protocolDefinition(protocols[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            namespaces.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            macros.count == 1,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            extensions.isEmpty
        {
            return .macro(macros[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            namespaces.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            !extensions.isEmpty
        {
            return .extensions(extensions)
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            enumerations.isEmpty,
            protocols.isEmpty,
            namespaces.count == 1,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            extensions.isEmpty
        {
            return .namespace(namespaces[0])
        }

        return .module(
            ModuleFileNode(
                mainBlock: mainBlock,
                states: topLevelStates,
                callables: topLevelCallables,
                constructs: constructs,
                namespaces: namespaces,
                enumerations: enumerations,
                protocols: protocols,
                macros: macros,
                precedenceGroups: precedenceGroups,
                operators: operators,
                extensions: extensions
            )
        )
    }

    public mutating func parseSourceFileForDeclarationDiscovery() throws -> SourceFileNode {
        currentStateTypes = [:]
        currentCallableReturnTypes = [:]

        var topLevelCallables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
        var namespaces: [NamespaceDeclaration] = []
        var macros: [MacroDeclaration] = []
        var precedenceGroups: [PrecedenceGroupDeclaration] = []
        var operators: [OperatorDeclaration] = []

        while peek() != .eof {
            if isMainBlockStart() {
                try skipMainBlockForDeclarationDiscovery()
                continue
            }

            if isStateDeclarationStart() {
                try skipStateDeclarationForDeclarationDiscovery()
                continue
            }

            if isCallableStart() {
                topLevelCallables.append(try parseCallableDeclaration(signatureOnly: true))
                continue
            }

            if isMacroDeclarationStart() {
                let declaration = try parseMacroDeclaration(signatureOnly: true)
                macros.append(declaration)
                registerMacroDeclaration(declaration)
                continue
            }

            if isNamespaceDeclarationStart() {
                namespaces.append(try parseNamespaceDeclarationForDeclarationDiscovery())
                continue
            }

            if isPrecedenceGroupDeclarationStart() {
                let declaration = try parsePrecedenceGroupDeclaration(requiresEOF: false)
                precedenceGroups.append(declaration)
                operatorEnvironment.register(precedenceGroup: declaration)
                continue
            }

            if isOperatorDeclarationStart() {
                let declaration = try parseOperatorDeclaration(requiresEOF: false)
                operators.append(declaration)
                operatorEnvironment.register(operator: declaration)
                continue
            }

            if peek() == .keyword(NeatSyntax.Keyword.typeExtension.rawValue) {
                _ = try parseExtensionDeclaration()
                continue
            }

            if isConstructDeclarationStart() || isBuilderDeclarationStart() {
                constructs.append(try parseConstructDeclarationForDeclarationDiscovery())
                continue
            }

            if isProtocolDeclarationStart() {
                _ = try parseProtocolDeclaration(requiresEOF: false)
                continue
            }

            if isEnumDeclarationStart() {
                _ = try parseEnumDeclaration(requiresEOF: false)
                continue
            }

            advance()
        }

        try consume(.eof)

        return .module(
            ModuleFileNode(
                mainBlock: nil,
                states: [],
                callables: topLevelCallables,
                constructs: constructs,
                namespaces: namespaces,
                enumerations: [],
                protocols: [],
                macros: macros,
                precedenceGroups: precedenceGroups,
                operators: operators,
                extensions: []
            )
        )
    }

}
