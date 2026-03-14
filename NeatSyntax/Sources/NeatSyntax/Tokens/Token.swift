import Foundation

enum Token: Equatable {
    case identifier(String)
    case hashDirective(String)
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
    case dot
    case colon
    case arrow
    case bang
    case equal
    case equalEqual
    case bangEqual
    case less
    case lessEqual
    case greater
    case greaterEqual
    case plus
    case plusEqual
    case andAnd
    case orOr
    case question
    case dollar
    case percent
    case comma
    case eof
}
