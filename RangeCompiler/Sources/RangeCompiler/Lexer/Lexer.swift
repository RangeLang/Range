import Foundation

// Boundary rule: lexer behavior belongs in RangeCompiler/Range/Lexer/*.range.
// This Swift file adapts the parser to the Range-authored bootstrap projection.

struct LexerForeignBody {
    let directive: String
    let language: String
}

struct Lexer {
    private let source: String
    private let foreignBodies: [LexerForeignBody]

    init(
        source: String,
        foreignBodies: [LexerForeignBody] = []
    ) {
        self.source = source
        self.foreignBodies = foreignBodies
    }

    mutating func tokenize() throws -> [LexedToken] {
        let lexer = RangeAuthoredLexer()
        let rangeForeignBodies = foreignBodies.map {
            RangeAuthoredLexerForeignBody(directive: $0.directive, language: $0.language)
        }
        switch lexer.tokenize(source: source, foreignBodies: rangeForeignBodies) {
        case .success(let tokens):
            return try tokens.map(Self.convertGenerated)
        case .failure(let error):
            throw ParseError(error.message, range: error.range)
        }
    }
}

// Bootstrap projection of RangeCompiler/Range/Lexer/Lexer.range.
struct RangeAuthoredLexer {
    func tokenize(
        source: String,
        foreignBodies: [RangeAuthoredLexerForeignBody]
    ) -> Result<[RangeAuthoredLexicalToken], RangeAuthoredLexingError> {
        var cursor = RangeAuthoredLexerCursor(
            source: source,
            foreignBodies: foreignBodies,
            rules: Self.generatedRules
        )
        return cursor.tokenize()
    }
}

struct RangeAuthoredLexerRule {
    let name: String
    let pattern: String
    let token: String
    let priority: Int
}

struct RangeAuthoredLexerForeignBody {
    let directive: String
    let language: String
}

struct RangeAuthoredLexingError: Error {
    let message: String
    let range: RangeSourceRange
}

struct RangeAuthoredLexerPosition {
    let index: Int
    let location: RangeSourceLocation
}

struct RangeAuthoredLexicalToken {
    let kind: RangeAuthoredTokenKind
    let range: RangeSourceRange
    let source: String
}

struct RangeAuthoredLexerCursor {
    let source: String
    let characters: [String]
    let foreignBodies: [RangeAuthoredLexerForeignBody]
    let rules: [RangeAuthoredLexerRule]
    var index: Int = 0
    var line: Int = 0
    var column: Int = 0
    var tokens: [RangeAuthoredLexicalToken] = []

    init(
        source: String,
        foreignBodies: [RangeAuthoredLexerForeignBody],
        rules: [RangeAuthoredLexerRule]
    ) {
        self.source = source
        self.characters = source.map(String.init)
        self.foreignBodies = foreignBodies
        self.rules = rules
    }

    mutating func tokenize() -> Result<[RangeAuthoredLexicalToken], RangeAuthoredLexingError> {
        while !isAtEnd() {
            if isWhitespace(currentCharacter()) {
                _ = advance()
                continue
            }

            let start = currentPosition()
            let character = currentCharacter()

            if matchLexerRuleLiteral(start: start) {
                continue
            } else if character == "\"" {
                switch readString(start: start) {
                case .success(let value):
                    emit(kind: .stringLiteral(value: value), start: start)
                case .failure(let error):
                    return .failure(error)
                }
            } else if character == "#" {
                if hasCharacter(offset: 1, value: "(") {
                    _ = advance()
                    emit(kind: .hash, start: start)
                } else if isHexDigitAt(offset: 1) {
                    switch readHexColorLiteral(start: start) {
                    case .success(let value):
                        emit(kind: .colorLiteral(value: value), start: start)
                    case .failure(let error):
                        return .failure(error)
                    }
                } else {
                    _ = advance()
                    emit(kind: .hash, start: start)
                }
            } else if character == "@" {
                switch readSigilIdentifier(start: start) {
                case .success(let identifier):
                    emit(kind: .macroAttribute(name: identifier, argument: nil), start: start)
                    let language = foreignBodyLanguage(directive: identifier)
                    if language != "" {
                        skipWhitespace()
                        if !isAtEnd() && currentCharacter() == "{" {
                            let braceStart = currentPosition()
                            _ = advance()
                            emit(kind: .leftBrace, start: braceStart)

                            let bodyStart = currentPosition()
                            switch readForeignBodyBlock(language: language, start: bodyStart) {
                            case .success(let body):
                                emit(
                                    kind: .foreignBody(language: language, text: body),
                                    start: bodyStart
                                )
                            case .failure(let error):
                                return .failure(error)
                            }

                            let closeStart = currentPosition()
                            if !match("}") {
                                return failure(
                                    message: "Unterminated @\(identifier) \(language) block.",
                                    start: start
                                )
                            }
                            emit(kind: .rightBrace, start: closeStart)
                        }
                    }
                case .failure(let error):
                    return .failure(error)
                }
            } else if character == "`" {
                switch readEscapedIdentifier(start: start) {
                case .success(let identifier):
                    emit(kind: .identifier(value: identifier), start: start)
                case .failure(let error):
                    return .failure(error)
                }
            } else if isDigit(character) {
                let token = readNumberLiteral(start: start)
                emit(kind: token, start: start)
            } else if isIdentifierStart(character) {
                let identifier = readIdentifier()
                if isKeyword(identifier) {
                    emit(kind: .keyword(value: identifier), start: start)
                } else {
                    emit(kind: .identifier(value: identifier), start: start)
                }
            } else {
                return failure(message: "Unexpected character \(character).", start: start)
            }
        }

        let eof = currentPosition()
        emit(kind: .eof, start: eof)
        return .success(tokens)
    }

    mutating func matchLexerRuleLiteral(start: RangeAuthoredLexerPosition) -> Bool {
        for rule in rules where isLiteralLexerRule(rule) && hasPrefix(rule.pattern) {
            advancePattern(rule.pattern)
            return emitRuleToken(token: rule.token, start: start)
        }
        return false
    }

    func isLiteralLexerRule(_ rule: RangeAuthoredLexerRule) -> Bool {
        isLiteralLexerToken(rule.token)
    }

    func isLiteralLexerToken(_ token: String) -> Bool {
        switch token {
        case "leftBrace", "rightBrace", "leftParen", "rightParen", "leftBracket", "rightBracket",
            "asterisk", "dot", "dotDotLess", "ellipsis", "colon", "arrow", "bang", "equal",
            "equalEqual", "bangEqual", "minus", "less", "lessEqual", "greater",
            "greaterEqual", "plus", "plusEqual", "slash", "ampersand", "andAnd", "pipe",
            "orOr", "question", "questionQuestion", "dollar", "percent", "comma":
            return true
        default:
            return false
        }
    }

    mutating func emitRuleToken(token: String, start: RangeAuthoredLexerPosition) -> Bool {
        switch token {
        case "leftBrace":
            emit(kind: .leftBrace, start: start)
        case "rightBrace":
            emit(kind: .rightBrace, start: start)
        case "leftParen":
            emit(kind: .leftParen, start: start)
        case "rightParen":
            emit(kind: .rightParen, start: start)
        case "leftBracket":
            emit(kind: .leftBracket, start: start)
        case "rightBracket":
            emit(kind: .rightBracket, start: start)
        case "asterisk":
            emit(kind: .asterisk, start: start)
        case "dot":
            emit(kind: .dot, start: start)
        case "dotDotLess":
            emit(kind: .dotDotLess, start: start)
        case "ellipsis":
            emit(kind: .ellipsis, start: start)
        case "colon":
            emit(kind: .colon, start: start)
        case "arrow":
            emit(kind: .arrow, start: start)
        case "bang":
            emit(kind: .bang, start: start)
        case "equal":
            emit(kind: .equal, start: start)
        case "equalEqual":
            emit(kind: .equalEqual, start: start)
        case "bangEqual":
            emit(kind: .bangEqual, start: start)
        case "minus":
            emit(kind: .minus, start: start)
        case "less":
            emit(kind: .less, start: start)
        case "lessEqual":
            emit(kind: .lessEqual, start: start)
        case "greater":
            emit(kind: .greater, start: start)
        case "greaterEqual":
            emit(kind: .greaterEqual, start: start)
        case "plus":
            emit(kind: .plus, start: start)
        case "plusEqual":
            emit(kind: .plusEqual, start: start)
        case "slash":
            emit(kind: .slash, start: start)
        case "ampersand":
            emit(kind: .ampersand, start: start)
        case "andAnd":
            emit(kind: .andAnd, start: start)
        case "pipe":
            emit(kind: .pipe, start: start)
        case "orOr":
            emit(kind: .orOr, start: start)
        case "question":
            emit(kind: .question, start: start)
        case "questionQuestion":
            emit(kind: .questionQuestion, start: start)
        case "dollar":
            emit(kind: .dollar, start: start)
        case "percent":
            emit(kind: .percent, start: start)
        case "comma":
            emit(kind: .comma, start: start)
        default:
            return false
        }
        return true
    }

    func hasPrefix(_ pattern: String) -> Bool {
        let patternCharacters = pattern.map(String.init)
        guard index + patternCharacters.count <= characters.count else {
            return false
        }
        return Array(characters[index..<(index + patternCharacters.count)]) == patternCharacters
    }

    mutating func advancePattern(_ pattern: String) {
        for _ in pattern {
            _ = advance()
        }
    }

    func isAtEnd() -> Bool {
        index >= characters.count
    }

    func currentCharacter() -> String {
        characters[index]
    }

    func hasCharacter(offset: Int, value: String) -> Bool {
        let position = index + offset
        if position >= characters.count {
            return false
        }
        return characters[position] == value
    }

    @discardableResult
    mutating func advance() -> String {
        let value = currentCharacter()
        index += 1
        if value == "\n" {
            line += 1
            column = 0
        } else {
            column += 1
        }
        return value
    }

    func currentLocation() -> RangeSourceLocation {
        RangeSourceLocation(line: line, character: column)
    }

    func currentPosition() -> RangeAuthoredLexerPosition {
        RangeAuthoredLexerPosition(index: index, location: currentLocation())
    }

    func range(from start: RangeAuthoredLexerPosition) -> RangeSourceRange {
        RangeSourceRange(start: start.location, end: currentLocation())
    }

    func sourceSlice(from start: RangeAuthoredLexerPosition) -> String {
        characters[start.index..<index].joined()
    }

    mutating func emit(kind: RangeAuthoredTokenKind, start: RangeAuthoredLexerPosition) {
        tokens.append(
            RangeAuthoredLexicalToken(
                kind: kind,
                range: range(from: start),
                source: sourceSlice(from: start)
            )
        )
    }

    func failure(
        message: String,
        start: RangeAuthoredLexerPosition
    ) -> Result<[RangeAuthoredLexicalToken], RangeAuthoredLexingError> {
        .failure(lexicalFailure(message: message, start: start))
    }

    func lexicalFailure(
        message: String,
        start: RangeAuthoredLexerPosition
    ) -> RangeAuthoredLexingError {
        RangeAuthoredLexingError(message: message, range: range(from: start))
    }

    mutating func match(_ expected: String) -> Bool {
        if isAtEnd() || currentCharacter() != expected {
            return false
        }
        _ = advance()
        return true
    }

    mutating func skipWhitespace() {
        while !isAtEnd() && isWhitespace(currentCharacter()) {
            _ = advance()
        }
    }

    mutating func readIdentifier() -> String {
        let start = index
        while !isAtEnd() && isIdentifierPart(currentCharacter()) {
            _ = advance()
        }
        return characters[start..<index].joined()
    }

    mutating func readEscapedIdentifier(
        start: RangeAuthoredLexerPosition
    ) -> Result<String, RangeAuthoredLexingError> {
        _ = advance()
        if isAtEnd() || !isIdentifierStart(currentCharacter()) {
            return .failure(lexicalFailure(message: "Expected identifier after `.", start: start))
        }

        let identifier = readIdentifier()

        if !match("`") {
            return .failure(
                lexicalFailure(message: "Unterminated escaped identifier.", start: start))
        }

        return .success(identifier)
    }

    mutating func readSigilIdentifier(
        start: RangeAuthoredLexerPosition
    ) -> Result<String, RangeAuthoredLexingError> {
        _ = advance()
        if isAtEnd() {
            return .failure(lexicalFailure(message: "Expected identifier after @.", start: start))
        }

        if currentCharacter() == "`" {
            return readEscapedIdentifier(start: start)
        }

        if !isASCIILetter(currentCharacter()) {
            return .failure(lexicalFailure(message: "Expected identifier after @.", start: start))
        }

        return .success(readIdentifier())
    }

    mutating func readHexColorLiteral(
        start: RangeAuthoredLexerPosition
    ) -> Result<String, RangeAuthoredLexingError> {
        _ = advance()
        var digits = ""
        while !isAtEnd() && isIdentifierPart(currentCharacter()) {
            digits += advance()
        }

        guard digits.count == 6, digits.allSatisfy({ isHexDigit(String($0)) }) else {
            return .failure(
                lexicalFailure(
                    message:
                        "Invalid hex color literal '#\(digits)'. Expected 6 hexadecimal digits.",
                    start: start
                )
            )
        }

        return .success(digits)
    }

    mutating func readNumberLiteral(start: RangeAuthoredLexerPosition) -> RangeAuthoredTokenKind {
        while !isAtEnd() && isDigit(currentCharacter()) {
            _ = advance()
        }

        if isAtEnd() || currentCharacter() != "." || !hasDigit(offset: 1) {
            let integerLiteral = characters[start.index..<index].joined()
            return .integer(value: integerLiteral)
        }

        _ = advance()
        while !isAtEnd() && isDigit(currentCharacter()) {
            _ = advance()
        }

        let raw = characters[start.index..<index].joined()

        if !isAtEnd() && currentCharacter() == "." && hasDigit(offset: 1) {
            _ = advance()
            while !isAtEnd() && isDigit(currentCharacter()) {
                _ = advance()
            }
            let versionLiteral = characters[start.index..<index].joined()
            return .stringLiteral(value: versionLiteral)
        }

        return .double(value: raw)
    }

    mutating func readString(
        start: RangeAuthoredLexerPosition
    ) -> Result<String, RangeAuthoredLexingError> {
        _ = advance()
        var result = ""
        var interpolationDepth = 0

        while !isAtEnd() {
            let character = currentCharacter()

            if character == "\"" && interpolationDepth == 0 {
                _ = advance()
                return .success(result)
            }

            if character == "\\" {
                _ = advance()
                if isAtEnd() {
                    return .failure(
                        lexicalFailure(
                            message: "Unterminated escape sequence in string literal.",
                            start: start
                        )
                    )
                }
                let escaped = advance()
                result += "\\" + escaped
                if escaped == "(" {
                    interpolationDepth += 1
                }
                continue
            }

            if interpolationDepth > 0 {
                if character == "\"" {
                    switch readInterpolatedStringLiteral(start: start) {
                    case .success(let value):
                        result += value
                    case .failure(let error):
                        return .failure(error)
                    }
                    continue
                }

                if character == "(" {
                    interpolationDepth += 1
                } else if character == ")" {
                    interpolationDepth -= 1
                }
            }

            result += character
            _ = advance()
        }

        return .failure(lexicalFailure(message: "Unterminated string literal.", start: start))
    }

    mutating func readInterpolatedStringLiteral(
        start: RangeAuthoredLexerPosition
    ) -> Result<String, RangeAuthoredLexingError> {
        var result = "\""
        _ = advance()

        while !isAtEnd() {
            let character = currentCharacter()
            result += character
            _ = advance()

            if character == "\\" {
                if isAtEnd() {
                    return .failure(
                        lexicalFailure(
                            message: "Unterminated escape sequence in string literal.",
                            start: start
                        )
                    )
                }
                let escaped = advance()
                result += escaped
                continue
            }

            if character == "\"" {
                return .success(result)
            }
        }

        return .failure(
            lexicalFailure(
                message: "Unterminated string literal inside interpolation.", start: start)
        )
    }

    mutating func readForeignBodyBlock(
        language: String,
        start: RangeAuthoredLexerPosition
    ) -> Result<String, RangeAuthoredLexingError> {
        var result = ""

        if !isAtEnd() && currentCharacter() == "\n" {
            _ = advance()
        }

        while !isAtEnd() {
            if currentCharacter() == "}" && isOnlyWhitespaceBeforeCurrentPositionOnLine() {
                return .success(trimNewlines(result))
            }

            result += currentCharacter()
            _ = advance()
        }

        return .failure(lexicalFailure(message: "Unterminated \(language) block.", start: start))
    }

    func isOnlyWhitespaceBeforeCurrentPositionOnLine() -> Bool {
        var position = index - 1
        while position >= 0 {
            let character = characters[position]
            if character == "\n" {
                return true
            }
            if !isWhitespace(character) {
                return false
            }
            position -= 1
        }
        return true
    }

    func trimNewlines(_ text: String) -> String {
        var start = 0
        var end = text.count

        while start < end && isNewlineAt(text: text, index: start) {
            start += 1
        }

        while end > start && isNewlineAt(text: text, index: end - 1) {
            end -= 1
        }

        return text.__rangeSubstring(start: start, end: end)
    }

    func foreignBodyLanguage(directive: String) -> String {
        for body in foreignBodies where body.directive == directive {
            return body.language
        }

        return ""
    }

    func hasDigit(offset: Int) -> Bool {
        let position = index + offset
        if position >= characters.count {
            return false
        }
        return isDigit(characters[position])
    }

    func isHexDigitAt(offset: Int) -> Bool {
        let position = index + offset
        if position >= characters.count {
            return false
        }
        return isHexDigit(characters[position])
    }

    func isHexDigit(_ value: String) -> Bool {
        guard let byte = singleASCIIByte(value) else {
            return false
        }
        return (byte >= CharacterBytes.zero && byte <= CharacterBytes.nine)
            || (byte >= CharacterBytes.lowerA && byte <= CharacterBytes.lowerF)
            || (byte >= CharacterBytes.upperA && byte <= CharacterBytes.upperF)
    }

    func isWhitespace(_ value: String) -> Bool {
        value == " " || value == "\n" || value == "\r" || value == "\t"
    }

    func isNewline(_ value: String) -> Bool {
        value == "\n" || value == "\r"
    }

    func isNewlineAt(text: String, index: Int) -> Bool {
        isNewline(text.__rangeCharacter(index: index))
    }

    func isDigit(_ value: String) -> Bool {
        guard let byte = singleASCIIByte(value) else {
            return false
        }
        return byte >= CharacterBytes.zero && byte <= CharacterBytes.nine
    }

    func isASCIILetter(_ value: String) -> Bool {
        guard let byte = singleASCIIByte(value) else {
            return false
        }
        return (byte >= CharacterBytes.lowerA && byte <= CharacterBytes.lowerZ)
            || (byte >= CharacterBytes.upperA && byte <= CharacterBytes.upperZ)
    }

    func isIdentifierStart(_ value: String) -> Bool {
        isASCIILetter(value) || value == "_"
    }

    func isIdentifierPart(_ value: String) -> Bool {
        isIdentifierStart(value) || isDigit(value)
    }

    func isKeyword(_ value: String) -> Bool {
        value == "let"
            || value == "state"
            || value == "binding"
            || value == "derived"
            || value == "extension"
            || value == "for"
            || value == "in"
            || value == "case"
            || value == "if"
            || value == "else"
            || value == "while"
            || value == "return"
            || value == "break"
            || value == "continue"
            || value == "switch"
            || value == "default"
            || value == "enum"
            || value == "protocol"
            || value == "construct"
            || value == "macro"
            || value == "open"
            || value == "closed"
            || value == "function"
            || value == "get"
            || value == "set"
            || value == "precedencegroup"
            || value == "infix"
            || value == "prefix"
            || value == "postfix"
            || value == "operator"
    }

    private func singleASCIIByte(_ value: String) -> UInt8? {
        guard value.utf8.count == 1 else {
            return nil
        }
        return value.utf8.first
    }
}

private enum CharacterBytes {
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let lowerA = UInt8(ascii: "a")
    static let lowerF = UInt8(ascii: "f")
    static let lowerZ = UInt8(ascii: "z")
    static let upperA = UInt8(ascii: "A")
    static let upperF = UInt8(ascii: "F")
    static let upperZ = UInt8(ascii: "Z")
}

extension String {
    fileprivate func __rangeCharacter(index: Int) -> String {
        let position = self.index(startIndex, offsetBy: index)
        return String(self[position])
    }

    fileprivate func __rangeSubstring(start: Int, end: Int) -> String {
        let lowerBound = self.index(startIndex, offsetBy: start)
        let upperBound = self.index(startIndex, offsetBy: end)
        return String(self[lowerBound..<upperBound])
    }
}
