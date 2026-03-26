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
            ]

            let operators = [
                OperatorDeclaration(
                    fixity: .infix,
                    symbol: "+",
                    precedenceGroup: "AdditionPrecedence"
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
    var currentEnvironmentTypes: [String: BootstrapType] = [:]
    var currentBindingNames: Set<String> = []
    var currentEnvironmentNames: Set<String> = []
    var currentMutableEnvironmentNames: Set<String> = []
    var currentSelfAvailable: Bool = false
    var currentExpressionTerminators: [Token] = []
    var operatorEnvironment: OperatorEnvironment

    public init(source: String) throws {
        var lexer = Lexer(source: source)
        self.tokens = try lexer.tokenize()
        self.operatorEnvironment = .bootstrap()
    }

    func isCurrentExpressionTerminator(_ token: Token) -> Bool {
        currentExpressionTerminators.contains(where: { $0 == token })
    }

    public mutating func parseSourceFile() throws -> SourceFileNode {
        currentStateTypes = [:]

        var mainBlock: MainBlockNode?
        var topLevelStates: [StateDeclaration] = []
        var topLevelCallables: [CallableDeclaration] = []
        var constructs: [ConstructDeclaration] = []
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

            if peek() == .keyword(NeatSyntax.Keyword.state.rawValue) {
                let state = try parseState()
                topLevelStates.append(state)
                currentStateTypes[state.name] = state.type
                continue
            }

            if isCallableStart() {
                topLevelCallables.append(try parseCallableDeclaration())
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
                macros.append(try parseMacroDeclaration())
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

        if let mainBlock,
            topLevelStates.isEmpty, topLevelCallables.isEmpty, enumerations.isEmpty,
            protocols.isEmpty,
            constructs.isEmpty,
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
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            extensions.isEmpty
        {
            return .construct(constructs[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
            protocols.isEmpty,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            enumerations.count == 1, extensions.isEmpty
        {
            return .enumeration(enumerations[0])
        }

        if mainBlock == nil, topLevelStates.isEmpty, topLevelCallables.isEmpty, constructs.isEmpty,
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
            enumerations.isEmpty,
            protocols.isEmpty,
            macros.isEmpty,
            precedenceGroups.isEmpty,
            operators.isEmpty,
            !extensions.isEmpty
        {
            return .extensions(extensions)
        }

        return .module(
            ModuleFileNode(
                mainBlock: mainBlock,
                states: topLevelStates,
                callables: topLevelCallables,
                constructs: constructs,
                enumerations: enumerations,
                protocols: protocols,
                macros: macros,
                precedenceGroups: precedenceGroups,
                operators: operators,
                extensions: extensions
            )
        )
    }

}
