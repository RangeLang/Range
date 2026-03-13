import Foundation

enum NeatSyntax {
    enum Keyword: String {
        case component
        case variable = "var"
        case constant = "let"
        case enumType = "enum"
        case typeExtension = "extension"
        case neatProtocol = "protocol"
        case projection = "on"
        case forLoop = "for"
        case inKeyword = "in"
        case caseBranch = "case"
        case function = "func"
        case switchStatement = "switch"
        case defaultBranch = "default"
    }
    static let keywordIdentifiers: Set<String> = Set(Keyword.allCases.map(\.rawValue))
    static let builtinTypeNames: [String] = BuiltinType.supportedNames

    static func declarationKind(for token: Token) -> DeclarationKind? {
        switch token {
        case .keyword(Keyword.component.rawValue):
            return .component
        case .atAttribute(let attribute, _):
            switch attribute {
            case "main": return .app
            case "StyleModifier": return nil
            default: return .component
            }
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
    static let supportedNames: [String] = [BuiltinType.int, .string, .bool, .dictionary, .void]
        .map(\.rawValue)
}
