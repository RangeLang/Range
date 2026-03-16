import Foundation

struct Lexer {
    private let characters: [Character]
    private var index: Int = 0

    init(source: String) {
        self.characters = Array(source)
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []

        while let character = peek() {
            if character.isWhitespace {
                advance()
                continue
            }

            switch character {
            case "/":
                advance()
                if match("/") {
                    skipLineComment()
                } else {
                    throw ParseError("Unexpected character /.")
                }
            case "{":
                advance()
                tokens.append(.leftBrace)
            case "}":
                advance()
                tokens.append(.rightBrace)
            case "(":
                advance()
                tokens.append(.leftParen)
            case ")":
                advance()
                tokens.append(.rightParen)
            case "[":
                advance()
                tokens.append(.leftBracket)
            case "]":
                advance()
                tokens.append(.rightBracket)
            case "*":
                advance()
                tokens.append(.asterisk)
            case ".":
                advance()
                if match(".") {
                    guard match(".") else {
                        throw ParseError("Unexpected character sequence ..")
                    }
                    tokens.append(.ellipsis)
                } else {
                    tokens.append(.dot)
                }
            case ":":
                advance()
                tokens.append(.colon)
            case "-":
                advance()
                if match(">") {
                    tokens.append(.arrow)
                } else {
                    throw ParseError("Unexpected character -.")
                }
            case "!":
                advance()
                if match("=") {
                    tokens.append(.bangEqual)
                } else {
                    tokens.append(.bang)
                }
            case ",":
                advance()
                tokens.append(.comma)
            case "=":
                advance()
                if match("=") {
                    tokens.append(.equalEqual)
                } else {
                    tokens.append(.equal)
                }
            case "<":
                advance()
                if match("=") {
                    tokens.append(.lessEqual)
                } else {
                    tokens.append(.less)
                }
            case ">":
                advance()
                if match("=") {
                    tokens.append(.greaterEqual)
                } else {
                    tokens.append(.greater)
                }
            case "+":
                advance()
                if match("=") {
                    tokens.append(.plusEqual)
                } else {
                    tokens.append(.plus)
                }
            case "?":
                advance()
                if match("?") {
                    tokens.append(.questionQuestion)
                } else {
                    tokens.append(.question)
                }
            case "$":
                advance()
                tokens.append(.dollar)
            case "&":
                advance()
                guard match("&") else {
                    throw ParseError("Unexpected character &.")
                }
                tokens.append(.andAnd)
            case "|":
                advance()
                guard match("|") else {
                    throw ParseError("Unexpected character |.")
                }
                tokens.append(.orOr)
            case "%":
                advance()
                tokens.append(.percent)
            case "\"":
                tokens.append(.stringLiteral(try readString()))
            case "#":
                let identifier = try readHashIdentifier()
                tokens.append(.hashDirective(identifier))
            case "@":
                let identifier = try readSigilIdentifier()
                tokens.append(.atAttribute(name: identifier, argument: nil))
            case "`":
                let identifier = try readEscapedIdentifier()
                tokens.append(.identifier(identifier))
            default:
                if character.isNumber {
                    tokens.append(try readNumberLiteral())
                } else if character.isLetter || character == "_" {
                    let identifier = readIdentifier()
                    if NeatSyntax.keywordIdentifiers.contains(identifier) {
                        tokens.append(.keyword(identifier))
                    } else {
                        tokens.append(.identifier(identifier))
                    }
                } else {
                    throw ParseError("Unexpected character \(character).")
                }
            }
        }

        tokens.append(.eof)
        return tokens
    }

    private func peek() -> Character? {
        guard index < characters.count else { return nil }
        return characters[index]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard index < characters.count else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    private mutating func match(_ expected: Character) -> Bool {
        guard peek() == expected else { return false }
        advance()
        return true
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while let character = peek(), character.isLetter || character.isNumber || character == "_" {
            advance()
        }
        return String(characters[start..<index])
    }

    private mutating func readEscapedIdentifier() throws -> String {
        advance()
        guard let next = peek(), next.isLetter || next == "_" else {
            throw ParseError("Expected identifier after `.")
        }

        let identifier = readIdentifier()

        guard match("`") else {
            throw ParseError("Unterminated escaped identifier.")
        }

        return identifier
    }

    private mutating func readSigilIdentifier() throws -> String {
        advance()
        guard let next = peek() else {
            throw ParseError("Expected identifier after @.")
        }
        if next == "`" {
            return try readEscapedIdentifier()
        }
        guard next.isLetter else {
            throw ParseError("Expected identifier after @.")
        }
        return readIdentifier()
    }

    private mutating func readHashIdentifier() throws -> String {
        advance()
        guard let next = peek() else {
            throw ParseError("Expected identifier after #.")
        }
        if next == "`" {
            return try readEscapedIdentifier()
        }
        guard next.isLetter else {
            throw ParseError("Expected identifier after #.")
        }
        return readIdentifier()
    }

    private mutating func readInteger() throws -> Int {
        let start = index
        while let character = peek(), character.isNumber {
            advance()
        }
        let value = String(characters[start..<index])
        guard let integer = Int(value) else {
            throw ParseError("Invalid integer literal \(value).")
        }
        return integer
    }

    private mutating func readNumberLiteral() throws -> Token {
        let integerPart = try readInteger()

        guard let character = peek(), character == ".", let next = peek(offset: 1), next.isNumber
        else {
            return .integer(integerPart)
        }

        advance()
        let fractionalStart = index
        while let character = peek(), character.isNumber {
            advance()
        }

        let fractionalPart = String(characters[fractionalStart..<index])
        let raw = "\(integerPart).\(fractionalPart)"
        guard let value = Double(raw) else {
            throw ParseError("Invalid numeric literal \(raw).")
        }
        return .double(value)
    }

    private func peek(offset: Int) -> Character? {
        let position = index + offset
        guard position < characters.count else { return nil }
        return characters[position]
    }

    private mutating func readString() throws -> String {
        advance()
        var result = ""
        var interpolationDepth = 0

        while let character = peek() {
            if character == "\"" && interpolationDepth == 0 {
                advance()
                return result
            }

            if character == "\\" {
                advance()
                guard let escaped = advance() else {
                    throw ParseError("Unterminated escape sequence in string literal.")
                }
                result.append("\\")
                result.append(escaped)
                if escaped == "(" {
                    interpolationDepth += 1
                }
                continue
            }

            if interpolationDepth > 0 {
                if character == "\"" {
                    result.append(try readInterpolatedStringLiteral())
                    continue
                }

                if character == "(" {
                    interpolationDepth += 1
                } else if character == ")" {
                    interpolationDepth -= 1
                }
            }

            result.append(character)
            advance()
        }

        throw ParseError("Unterminated string literal.")
    }

    private mutating func readInterpolatedStringLiteral() throws -> String {
        var result = "\""
        advance()

        while let character = peek() {
            result.append(character)
            advance()

            if character == "\\" {
                guard let escaped = advance() else {
                    throw ParseError("Unterminated escape sequence in string literal.")
                }
                result.append(escaped)
                continue
            }

            if character == "\"" {
                return result
            }
        }

        throw ParseError("Unterminated string literal inside interpolation.")
    }

    private mutating func skipLineComment() {
        while let character = peek(), character != "\n" {
            advance()
        }
    }
}
