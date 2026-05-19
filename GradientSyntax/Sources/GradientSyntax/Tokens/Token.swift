import Foundation

enum Token: Equatable {
    case hash
    case identifier(String)
    case hashDirective(String)
    case foreignBody(language: String, text: String)
    case stringLiteral(String)
    case integer(Int)
    case double(Double)
    case keyword(String)
    case atAttribute(name: String, argument: String?)
    case leftBrace
    case rightBrace
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case asterisk
    case dot
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
    case andAnd
    case orOr
    case question
    case questionQuestion
    case dollar
    case percent
    case comma
    case eof

    var isForeignBody: Bool {
        if case .foreignBody = self {
            return true
        }
        return false
    }
}

struct LexedToken {
    let token: Token
    let range: GradientSourceRange
}
