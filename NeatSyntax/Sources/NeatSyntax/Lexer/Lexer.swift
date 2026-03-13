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
            case ".":
                advance()
                tokens.append(.dot)
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
            case ",":
                advance()
                tokens.append(.comma)
            case "=":
                advance()
                tokens.append(.equal)
            case "+":
                advance()
                if match("=") {
                    tokens.append(.plusEqual)
                } else {
                    tokens.append(.plus)
                }
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
                let argument = try readSigilArgumentIfPresent()
                if identifier == "State" {
                    tokens.append(.atState)
                } else {
                    tokens.append(.atAttribute(name: identifier, argument: argument))
                }
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

    private mutating func readSigilIdentifier() throws -> String {
        advance()
        guard let next = peek(), next.isLetter else {
            throw ParseError("Expected identifier after @.")
        }
        return readIdentifier()
    }

    private mutating func readHashIdentifier() throws -> String {
        advance()
        guard let next = peek(), next.isLetter else {
            throw ParseError("Expected identifier after #.")
        }
        return readIdentifier()
    }

    private mutating func readSigilArgumentIfPresent() throws -> String? {
        guard peek() == "(" else {
            return nil
        }

        advance()
        let start = index

        while let character = peek(), character != ")" {
            guard character.isLetter || character.isNumber || character == "_" || character == "."
            else {
                throw ParseError("Invalid attribute argument.")
            }
            advance()
        }

        guard peek() == ")" else {
            throw ParseError("Unterminated attribute argument list.")
        }

        let value = String(characters[start..<index])
        advance()

        guard !value.isEmpty else {
            throw ParseError("Expected attribute argument.")
        }

        return value
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

        while let character = peek() {
            if character == "\"" {
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
                continue
            }

            result.append(character)
            advance()
        }

        throw ParseError("Unterminated string literal.")
    }

    private mutating func skipLineComment() {
        while let character = peek(), character != "\n" {
            advance()
        }
    }
}
