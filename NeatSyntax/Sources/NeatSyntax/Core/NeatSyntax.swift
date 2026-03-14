import Foundation

enum NeatSyntax {
    enum Keyword: String {
        case component
        case variable = "var"
        case constant = "let"
        case state = "state"
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
    }
    static let keywordIdentifiers: Set<String> = Set(Keyword.allCases.map(\.rawValue))
    static let builtinTypeNames: [String] = BuiltinType.supportedNames

    static func declarationKind(for token: Token) -> DeclarationKind? {
        switch token {
        case .hashDirective:
            return .declaration
        default:
            return nil
        }
    }

    static func attributeApplication(for token: Token) -> AttributeApplication? {
        guard case .hashDirective(let name) = token else {
            return nil
        }
        return AttributeApplication(name: name, argument: nil)
    }
}

extension NeatSyntax.Keyword: CaseIterable {}

extension BuiltinType {
    static let supportedNames: [String] = ["Int", "String", "Bool", "Dictionary", "Void"]
}
