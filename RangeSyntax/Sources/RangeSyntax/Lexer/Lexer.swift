import Foundation

struct Lexer {
    private let characters: [Character]
    private let foreignBodyLanguage: (String) -> String?
    private var index: Int = 0
    private var line: Int = 0
    private var character: Int = 0

    init(
        source: String,
        foreignBodyLanguage: @escaping (String) -> String? = { _ in nil }
    ) {
        self.characters = Array(source)
        self.foreignBodyLanguage = foreignBodyLanguage
    }

    mutating func tokenize() throws -> [LexedToken] {
        var tokens: [LexedToken] = []

        func emit(_ token: Token, start: GradientSourceLocation) {
            tokens.append(LexedToken(token: token, range: range(from: start)))
        }

        while let character = peek() {
            if character.isWhitespace {
                advance()
                continue
            }

            let start = currentLocation()
            switch character {
            case "/":
                advance()
                if match("/") {
                    throw ParseError(
                        "Line comments are not Gradient syntax. Use a marker such as #description { ... } for source notes.",
                        range: range(from: start)
                    )
                } else {
                    emit(.slash, start: start)
                }
            case "{":
                advance()
                emit(.leftBrace, start: start)
            case "}":
                advance()
                emit(.rightBrace, start: start)
            case "(":
                advance()
                emit(.leftParen, start: start)
            case ")":
                advance()
                emit(.rightParen, start: start)
            case "[":
                advance()
                emit(.leftBracket, start: start)
            case "]":
                advance()
                emit(.rightBracket, start: start)
            case "*":
                advance()
                emit(.asterisk, start: start)
            case ".":
                advance()
                if match(".") {
                    guard match(".") else {
                        throw ParseError("Unexpected character sequence ..", range: range(from: start))
                    }
                    emit(.ellipsis, start: start)
                } else {
                    emit(.dot, start: start)
                }
            case ":":
                advance()
                emit(.colon, start: start)
            case "-":
                advance()
                if match(">") {
                    emit(.arrow, start: start)
                } else {
                    emit(.minus, start: start)
                }
            case "!":
                advance()
                if match("=") {
                    emit(.bangEqual, start: start)
                } else {
                    emit(.bang, start: start)
                }
            case ",":
                advance()
                emit(.comma, start: start)
            case "=":
                advance()
                if match("=") {
                    emit(.equalEqual, start: start)
                } else {
                    emit(.equal, start: start)
                }
            case "<":
                advance()
                if match("=") {
                    emit(.lessEqual, start: start)
                } else {
                    emit(.less, start: start)
                }
            case ">":
                advance()
                if match("=") {
                    emit(.greaterEqual, start: start)
                } else {
                    emit(.greater, start: start)
                }
            case "+":
                advance()
                if match("=") {
                    emit(.plusEqual, start: start)
                } else {
                    emit(.plus, start: start)
                }
            case "?":
                advance()
                if match("?") {
                    emit(.questionQuestion, start: start)
                } else {
                    emit(.question, start: start)
                }
            case "$":
                advance()
                emit(.dollar, start: start)
            case "&":
                advance()
                guard match("&") else {
                    throw ParseError("Unexpected character &.", range: range(from: start))
                }
                emit(.andAnd, start: start)
            case "|":
                advance()
                guard match("|") else {
                    throw ParseError("Unexpected character |.", range: range(from: start))
                }
                emit(.orOr, start: start)
            case "%":
                advance()
                emit(.percent, start: start)
            case "\"":
                emit(.stringLiteral(try readString(start: start)), start: start)
            case "#":
                if peek(offset: 1) == "(" {
                    advance()
                    emit(.hash, start: start)
                } else {
                    let identifier = try readHashIdentifier(start: start)
                    emit(.hashDirective(identifier), start: start)
                    if let language = foreignBodyLanguage(identifier) {
                        skipWhitespace()
                        if peek() == "{" {
                            let braceStart = currentLocation()
                            advance()
                            emit(.leftBrace, start: braceStart)

                            let bodyStart = currentLocation()
                            let body = try readForeignBodyBlock(language: language, start: bodyStart)
                            emit(.foreignBody(language: language, text: body), start: bodyStart)

                            let closeStart = currentLocation()
                            guard match("}") else {
                                throw ParseError("Unterminated #\(identifier) \(language) block.", range: range(from: start))
                            }
                            emit(.rightBrace, start: closeStart)
                        }
                    }
                }
            case "@":
                let identifier = try readSigilIdentifier(start: start)
                emit(.atAttribute(name: identifier, argument: nil), start: start)
            case "`":
                let identifier = try readEscapedIdentifier(start: start)
                emit(.identifier(identifier), start: start)
            default:
                if character.isNumber {
                    emit(try readNumberLiteral(start: start), start: start)
                } else if character.isLetter || character == "_" {
                    let identifier = readIdentifier()
                    if GradientSyntax.keywordIdentifiers.contains(identifier) {
                        emit(.keyword(identifier), start: start)
                    } else {
                        emit(.identifier(identifier), start: start)
                    }
                } else {
                    throw ParseError("Unexpected character \(character).", range: range(from: start))
                }
            }
        }

        let eof = currentLocation()
        tokens.append(LexedToken(token: .eof, range: GradientSourceRange(start: eof, end: eof)))
        return tokens
    }

    private func peek() -> Character? {
        guard index < characters.count else { return nil }
        return characters[index]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard index < characters.count else { return nil }
        let value = characters[index]
        index += 1
        if value == "\n" {
            line += 1
            character = 0
        } else {
            character += 1
        }
        return value
    }

    private func currentLocation() -> GradientSourceLocation {
        GradientSourceLocation(line: line, character: character)
    }

    private func range(from start: GradientSourceLocation) -> GradientSourceRange {
        GradientSourceRange(start: start, end: currentLocation())
    }

    private mutating func match(_ expected: Character) -> Bool {
        guard peek() == expected else { return false }
        advance()
        return true
    }

    private mutating func skipWhitespace() {
        while let character = peek(), character.isWhitespace {
            advance()
        }
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while let character = peek(), character.isLetter || character.isNumber || character == "_" {
            advance()
        }
        return String(characters[start..<index])
    }

    private mutating func readEscapedIdentifier(start: GradientSourceLocation) throws -> String {
        advance()
        guard let next = peek(), next.isLetter || next == "_" else {
            throw ParseError("Expected identifier after `.", range: range(from: start))
        }

        let identifier = readIdentifier()

        guard match("`") else {
            throw ParseError("Unterminated escaped identifier.", range: range(from: start))
        }

        return identifier
    }

    private mutating func readSigilIdentifier(start: GradientSourceLocation) throws -> String {
        advance()
        guard let next = peek() else {
            throw ParseError("Expected identifier after @.", range: range(from: start))
        }
        if next == "`" {
            return try readEscapedIdentifier(start: start)
        }
        guard next.isLetter else {
            throw ParseError("Expected identifier after @.", range: range(from: start))
        }
        return readIdentifier()
    }

    private mutating func readHashIdentifier(start: GradientSourceLocation) throws -> String {
        advance()
        guard let next = peek() else {
            throw ParseError("Expected identifier after #.", range: range(from: start))
        }
        if next == "`" {
            return try readEscapedIdentifier(start: start)
        }
        guard next.isLetter else {
            throw ParseError("Expected identifier after #.", range: range(from: start))
        }
        return readIdentifier()
    }

    private mutating func readInteger(start: GradientSourceLocation) throws -> Int {
        let digitStart = index
        while let character = peek(), character.isNumber {
            advance()
        }
        let value = String(characters[digitStart..<index])
        guard let integer = Int(value) else {
            throw ParseError("Invalid integer literal \(value).", range: range(from: start))
        }
        return integer
    }

    private mutating func readNumberLiteral(start: GradientSourceLocation) throws -> Token {
        let integerPart = try readInteger(start: start)

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

        if peek() == ".", let next = peek(offset: 1), next.isNumber {
            advance()
            let patchStart = index
            while let character = peek(), character.isNumber {
                advance()
            }
            let patchPart = String(characters[patchStart..<index])
            return .stringLiteral("\(raw).\(patchPart)")
        }

        guard let value = Double(raw) else {
            throw ParseError("Invalid numeric literal \(raw).", range: range(from: start))
        }
        return .double(value)
    }

    private func peek(offset: Int) -> Character? {
        let position = index + offset
        guard position < characters.count else { return nil }
        return characters[position]
    }

    private mutating func readString(start: GradientSourceLocation) throws -> String {
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
                    throw ParseError("Unterminated escape sequence in string literal.", range: range(from: start))
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
                    result.append(try readInterpolatedStringLiteral(start: start))
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

        throw ParseError("Unterminated string literal.", range: range(from: start))
    }

    private mutating func readInterpolatedStringLiteral(start: GradientSourceLocation) throws -> String {
        var result = "\""
        advance()

        while let character = peek() {
            result.append(character)
            advance()

            if character == "\\" {
                guard let escaped = advance() else {
                    throw ParseError("Unterminated escape sequence in string literal.", range: range(from: start))
                }
                result.append(escaped)
                continue
            }

            if character == "\"" {
                return result
            }
        }

        throw ParseError("Unterminated string literal inside interpolation.", range: range(from: start))
    }

    private mutating func readForeignBodyBlock(language: String, start: GradientSourceLocation) throws -> String {
        var result = ""

        if peek() == "\n" {
            advance()
        }

        while let character = peek() {
            if character == "}" && isOnlyWhitespaceBeforeCurrentPositionOnLine() {
                return result.trimmingCharacters(in: .newlines)
            }

            result.append(character)
            advance()
        }

        throw ParseError("Unterminated \(language) block.", range: range(from: start))
    }

    private func isOnlyWhitespaceBeforeCurrentPositionOnLine() -> Bool {
        var position = index - 1
        while position >= 0 {
            let character = characters[position]
            if character == "\n" {
                return true
            }
            if !character.isWhitespace {
                return false
            }
            position -= 1
        }
        return true
    }
}
