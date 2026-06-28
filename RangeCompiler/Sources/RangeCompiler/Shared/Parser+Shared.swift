import Foundation

extension Parser {
    mutating func skipUnknownBlockBody() throws {
        var depth = 0
        while true {
            switch peek() {
            case .leftBrace:
                depth += 1
                advance()
            case .rightBrace:
                if depth == 0 {
                    return
                }
                depth -= 1
                advance()
            case .eof:
                throw ParseError("Unterminated declaration block.")
            default:
                advance()
            }
        }
    }

    mutating func skipGenericParameterClauseIfPresent() throws {
        guard peek() == .less else {
            return
        }

        var depth = 0
        while true {
            switch peek() {
            case .less:
                depth += 1
                advance()
            case .greater:
                depth -= 1
                advance()
                if depth == 0 {
                    return
                }
            case .eof:
                throw ParseError("Unterminated generic parameter clause.")
            default:
                advance()
            }
        }
    }
}
