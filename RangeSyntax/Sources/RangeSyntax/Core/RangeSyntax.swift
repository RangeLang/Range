import Foundation

enum RangeSyntax {
    enum Attribute: String, CaseIterable {
        case main = "main"
        case background = "background"
        case `defer` = "defer"
        case core = "core"
        case package = "package"
        case expand = "expand"
    }

    enum Keyword: String {
        case namespace = "namespace"
        case `let` = "let"
        case state = "state"
        case binding = "binding"
        case derived = "derived"
        case typeExtension = "extension"
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
        case enumeration = "enum"
        case protocolDefinition = "protocol"
        case construct = "construct"
        case macro = "macro"
        case open = "open"
        case closed = "closed"
        case function = "function"
        case getter = "get"
        case setter = "set"
        case `precedencegroup` = "precedencegroup"
        case infix = "infix"
        case prefix = "prefix"
        case postfix = "postfix"
        case operatorKeyword = "operator"
    }
    static let keywordIdentifiers: Set<String> = Set(Keyword.allCases.map(\.rawValue))
    static let attributeIdentifiers: Set<String> = Set(Attribute.allCases.map(\.rawValue))

    static func constructKind(for token: Token) -> ConstructKind? {
        switch token {
        case .keyword(Keyword.construct.rawValue):
            return .declaration
        default:
            return nil
        }
    }

    static func attributeApplication(for token: Token) -> AttributeApplication? {
        guard case .macroAttribute(let name, let argument) = token else {
            return nil
        }
        return AttributeApplication(name: name, argument: argument)
    }
}

extension RangeSyntax.Keyword: CaseIterable {}
