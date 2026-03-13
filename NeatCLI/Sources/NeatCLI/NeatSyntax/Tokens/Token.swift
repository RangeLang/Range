import Foundation

enum Token: Equatable {
    case identifier(String)
    case stringLiteral(String)
    case integer(Int)
    case double(Double)
    case keyword(String)
    case atState
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
    case equal
    case plus
    case plusEqual
    case percent
    case comma
    case eof
}
