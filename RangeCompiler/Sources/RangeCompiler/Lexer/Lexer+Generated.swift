import Foundation

// Swift token projection for the current compiler lexer.

enum SwiftTokenKind {
    case hash
    case identifier(value: String)
    case foreignBody(language: String, text: String)
    case stringLiteral(value: String)
    case integer(value: String)
    case double(value: String)
    case keyword(value: String)
    case macroAttribute(name: String, argument: String?)
    case leftBrace
    case rightBrace
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case asterisk
    case dot
    case dotDotLess
    case ellipsis
    case colon
    case arrow
    case bang
    case equal
    case equalEqual
    case bangEqual
    case minus
    case less
    case lessEqual
    case greater
    case greaterEqual
    case plus
    case plusEqual
    case slash
    case ampersand
    case andAnd
    case pipe
    case orOr
    case question
    case questionQuestion
    case dollar
    case percent
    case comma
    case eof
}

extension Lexer {
    static func convertGenerated(_ token: SwiftLexicalToken) throws -> LexedToken {
        let parserToken: Token
        switch token.kind {
        case .hash:
            parserToken = .hash
        case .identifier(let value):
            parserToken = .identifier(value)
        case .foreignBody(let language, let text):
            parserToken = .foreignBody(language: language, text: text)
        case .stringLiteral(let value):
            parserToken = .stringLiteral(value)
        case .integer(let value):
            guard let integer = Int(value) else {
                throw ParseError("Invalid integer literal \(value).", range: token.range)
            }
            parserToken = .integer(integer)
        case .double(let value):
            guard let double = Double(value) else {
                throw ParseError("Invalid numeric literal \(value).", range: token.range)
            }
            parserToken = .double(double)
        case .keyword(let value):
            parserToken = .keyword(value)
        case .macroAttribute(let name, let argument):
            parserToken = .macroAttribute(name: name, argument: argument)
        case .leftBrace:
            parserToken = .leftBrace
        case .rightBrace:
            parserToken = .rightBrace
        case .leftParen:
            parserToken = .leftParen
        case .rightParen:
            parserToken = .rightParen
        case .leftBracket:
            parserToken = .leftBracket
        case .rightBracket:
            parserToken = .rightBracket
        case .asterisk:
            parserToken = .asterisk
        case .dot:
            parserToken = .dot
        case .dotDotLess:
            parserToken = .dotDotLess
        case .ellipsis:
            parserToken = .ellipsis
        case .colon:
            parserToken = .colon
        case .arrow:
            parserToken = .arrow
        case .bang:
            parserToken = .bang
        case .equal:
            parserToken = .equal
        case .equalEqual:
            parserToken = .equalEqual
        case .bangEqual:
            parserToken = .bangEqual
        case .minus:
            parserToken = .minus
        case .less:
            parserToken = .less
        case .lessEqual:
            parserToken = .lessEqual
        case .greater:
            parserToken = .greater
        case .greaterEqual:
            parserToken = .greaterEqual
        case .plus:
            parserToken = .plus
        case .plusEqual:
            parserToken = .plusEqual
        case .slash:
            parserToken = .slash
        case .ampersand:
            parserToken = .ampersand
        case .andAnd:
            parserToken = .andAnd
        case .pipe:
            parserToken = .pipe
        case .orOr:
            parserToken = .orOr
        case .question:
            parserToken = .question
        case .questionQuestion:
            parserToken = .questionQuestion
        case .dollar:
            parserToken = .dollar
        case .percent:
            parserToken = .percent
        case .comma:
            parserToken = .comma
        case .eof:
            parserToken = .eof
        }
        return LexedToken(token: parserToken, range: token.range)
    }
}

extension SwiftLexer {
    static let generatedRules: [SwiftLexerRule] = [
        SwiftLexerRule(
            name: "whitespace", pattern: "whitespace+", token: "skip", priority: 0),
        SwiftLexerRule(name: "leftBrace", pattern: "{", token: "leftBrace", priority: 20),
        SwiftLexerRule(name: "rightBrace", pattern: "}", token: "rightBrace", priority: 20),
        SwiftLexerRule(name: "leftParen", pattern: "(", token: "leftParen", priority: 20),
        SwiftLexerRule(name: "rightParen", pattern: ")", token: "rightParen", priority: 20),
        SwiftLexerRule(
            name: "leftBracket", pattern: "[", token: "leftBracket", priority: 20),
        SwiftLexerRule(
            name: "rightBracket", pattern: "]", token: "rightBracket", priority: 20),
        SwiftLexerRule(
            name: "dotDotLess", pattern: "..<", token: "dotDotLess", priority: 30),
        SwiftLexerRule(name: "ellipsis", pattern: "...", token: "ellipsis", priority: 30),
        SwiftLexerRule(name: "dot", pattern: ".", token: "dot", priority: 20),
        SwiftLexerRule(name: "arrow", pattern: "->", token: "arrow", priority: 30),
        SwiftLexerRule(name: "minus", pattern: "-", token: "minus", priority: 20),
        SwiftLexerRule(name: "bangEqual", pattern: "!=", token: "bangEqual", priority: 30),
        SwiftLexerRule(name: "bang", pattern: "!", token: "bang", priority: 20),
        SwiftLexerRule(
            name: "equalEqual", pattern: "==", token: "equalEqual", priority: 30),
        SwiftLexerRule(name: "equal", pattern: "=", token: "equal", priority: 20),
        SwiftLexerRule(name: "lessEqual", pattern: "<=", token: "lessEqual", priority: 30),
        SwiftLexerRule(name: "less", pattern: "<", token: "less", priority: 20),
        SwiftLexerRule(
            name: "greaterEqual", pattern: ">=", token: "greaterEqual", priority: 30),
        SwiftLexerRule(name: "greater", pattern: ">", token: "greater", priority: 20),
        SwiftLexerRule(name: "plusEqual", pattern: "+=", token: "plusEqual", priority: 30),
        SwiftLexerRule(name: "plus", pattern: "+", token: "plus", priority: 20),
        SwiftLexerRule(
            name: "questionQuestion", pattern: "??", token: "questionQuestion", priority: 30),
        SwiftLexerRule(name: "question", pattern: "?", token: "question", priority: 20),
        SwiftLexerRule(name: "andAnd", pattern: "&&", token: "andAnd", priority: 30),
        SwiftLexerRule(name: "orOr", pattern: "||", token: "orOr", priority: 30),
        SwiftLexerRule(name: "asterisk", pattern: "*", token: "asterisk", priority: 20),
        SwiftLexerRule(name: "colon", pattern: ":", token: "colon", priority: 20),
        SwiftLexerRule(name: "comma", pattern: ",", token: "comma", priority: 20),
        SwiftLexerRule(name: "slash", pattern: "/", token: "slash", priority: 20),
        SwiftLexerRule(name: "ampersand", pattern: "&", token: "ampersand", priority: 20),
        SwiftLexerRule(name: "dollar", pattern: "$", token: "dollar", priority: 20),
        SwiftLexerRule(name: "percent", pattern: "%", token: "percent", priority: 20),
        SwiftLexerRule(name: "pipe", pattern: "|", token: "pipe", priority: 20),
        SwiftLexerRule(
            name: "stringLiteral", pattern: "quotedString", token: "stringLiteral", priority: 40),
        SwiftLexerRule(name: "hash", pattern: "#(", token: "hash", priority: 50),
        SwiftLexerRule(
            name: "macroAttribute", pattern: "@identifier", token: "macroAttribute", priority: 40),
        SwiftLexerRule(
            name: "escapedIdentifier", pattern: "`identifier`", token: "identifier", priority: 40),
        SwiftLexerRule(
            name: "double", pattern: "digits.digits", token: "double", priority: 40),
        SwiftLexerRule(name: "integer", pattern: "digits", token: "integer", priority: 30),
        SwiftLexerRule(
            name: "keyword", pattern: "keywordIdentifier", token: "keyword", priority: 40),
        SwiftLexerRule(
            name: "identifier", pattern: "identifier", token: "identifier", priority: 30),
        SwiftLexerRule(name: "eof", pattern: "end", token: "eof", priority: 0),
    ]
}
