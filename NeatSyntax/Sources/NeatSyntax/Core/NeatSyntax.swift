import Foundation

enum NeatSyntax {
    enum Keyword: String {
        case value = "value"
        case state = "state"
        case environment = "environment"
        case binding = "binding"
        case derived = "derived"
        case typeExtension = "extension"
        case projection = "on"
        case forLoop = "for"
        case inKeyword = "in"
        case caseBranch = "case"
        case ifStatement = "if"
        case elseBranch = "else"
        case whileLoop = "while"
        case returnStatement = "return"
        case breakStatement = "break"
        case continueStatement = "continue"
        case switchStatement = "switch"
        case defaultBranch = "default"
        case primitive = "primitive"
        case enumeration = "enum"
        case protocolDefinition = "protocol"
        case construct = "construct"
        case function = "function"
        case getter = "get"
        case setter = "set"
    }
    static let keywordIdentifiers: Set<String> = Set(Keyword.allCases.map(\.rawValue))
    static let builtinTypeNames: [String] = BuiltinType.supportedNames

    static func constructKind(for token: Token) -> ConstructKind? {
        switch token {
        case .keyword(Keyword.construct.rawValue):
            return .declaration
        default:
            return nil
        }
    }

    static func attributeApplication(for token: Token) -> AttributeApplication? {
        guard case .atAttribute(let name, let argument) = token else {
            return nil
        }
        return AttributeApplication(name: name, argument: argument)
    }
}

extension NeatSyntax.Keyword: CaseIterable {}

extension BuiltinType {
    static let supportedNames: [String] = [
        "Int",
        "Double",
        "Float",
        "String",
        "Bool",
        "Data",
        "Dictionary",
        "Set",
        "Void",
    ]
}
