import Foundation

extension Parser {
    func isMainBlockStart() -> Bool {
        guard case .macroAttribute(let name, nil) = peek(), name == "main" else {
            return false
        }
        return peek(offset: 1) == .leftBrace
    }

    func isTopLevelBlockMacroStart() -> Bool {
        topLevelBlockMacroOffset() != nil
    }

    public mutating func parseMainBlock(requiresEOF: Bool = true) throws -> MainBlockNode {
        guard case .macroAttribute(let name, nil) = peek(), name == "main" else {
            throw ParseError("Expected @main block.")
        }
        advance()
        let body = try parseStatementBlock(baseLocalBindings: [:])
        if requiresEOF {
            try consume(.eof)
        }
        return MainBlockNode(
            macros: [MacroApplication(name: name, genericArguments: [], argumentClause: nil)],
            body: body
        )
    }

    mutating func parseTopLevelBlockMacro() throws -> BlockMacroNode {
        guard isTopLevelBlockMacroStart() else {
            throw ParseError("Expected top-level block macro.")
        }
        var applications: [MacroApplication] = []
        while true {
            guard case .macroAttribute(let name, _) = peek(), name != "main" else {
                throw ParseError("Expected top-level block macro.")
            }
            let blockFollows = currentMacroApplicationIsFollowedByBlock()
            advance()
            let genericArguments = try parseMacroGenericArgumentsIfPresent()
            let argumentClause = try parseMacroArgumentClauseIfPresent()
            if blockFollows {
                let rawBody = try renderUpcomingBlockBody()
                let body = try parseStatementBlock(baseLocalBindings: [:])
                applications.append(
                    MacroApplication(
                        name: name,
                        genericArguments: genericArguments,
                        argumentClause: argumentClause,
                        rawBody: rawBody
                    )
                )
                return BlockMacroNode(macros: applications, body: body, rawBody: rawBody)
            }
            applications.append(
                MacroApplication(
                    name: name,
                    genericArguments: genericArguments,
                    argumentClause: argumentClause
                )
            )
        }
    }

    mutating func skipTopLevelBlockMacroForDeclarationDiscovery() throws {
        guard isTopLevelBlockMacroStart() else {
            throw ParseError("Expected top-level block macro.")
        }
        while true {
            guard case .macroAttribute(let name, _) = peek(), name != "main" else {
                throw ParseError("Expected top-level block macro.")
            }
            let blockFollows = currentMacroApplicationIsFollowedByBlock()
            advance()
            try skipGenericParameterClauseIfPresent()
            if peek() == .leftParen {
                try skipParenthesizedClause()
            }
            if blockFollows {
                try consume(.leftBrace)
                try skipUnknownBlockBody()
                try consume(.rightBrace)
                return
            }
        }
    }

    private func topLevelBlockMacroOffset() -> Int? {
        var offset = 0
        while case .macroAttribute(let name, _) = peek(offset: offset),
            name != "main",
            isMacroApplicationAttribute(name)
        {
            guard let endOffset = macroApplicationEndOffset(startingAt: offset) else {
                return nil
            }
            if peek(offset: endOffset) == .leftBrace {
                return offset
            }
            offset = endOffset
        }
        return nil
    }

    private func currentMacroApplicationIsFollowedByBlock() -> Bool {
        guard let endOffset = macroApplicationEndOffset(startingAt: 0) else {
            return false
        }
        return peek(offset: endOffset) == .leftBrace
    }

    private func macroApplicationEndOffset(startingAt startOffset: Int) -> Int? {
        var offset = startOffset + 1
        if peek(offset: offset) == .less {
            var depth = 1
            offset += 1
            while depth > 0 {
                switch peek(offset: offset) {
                case .less:
                    depth += 1
                case .greater:
                    depth -= 1
                case .eof:
                    return nil
                default:
                    break
                }
                offset += 1
            }
        }
        if peek(offset: offset) == .leftParen {
            var depth = 1
            offset += 1
            while depth > 0 {
                switch peek(offset: offset) {
                case .leftParen:
                    depth += 1
                case .rightParen:
                    depth -= 1
                case .eof:
                    return nil
                default:
                    break
                }
                offset += 1
            }
        }
        return offset
    }

    private mutating func skipParenthesizedClause() throws {
        var depth = 0
        repeat {
            switch peek() {
            case .leftParen:
                depth += 1
            case .rightParen:
                depth -= 1
            case .eof:
                throw ParseError("Unterminated macro argument clause.")
            default:
                break
            }
            advance()
        } while depth > 0
    }

    private func renderUpcomingBlockBody() throws -> String {
        guard peek() == .leftBrace else {
            throw ParseError("Expected block macro body.")
        }
        var depth = 0
        var offset = 1
        var parts: [String] = []
        while true {
            let token = peek(offset: offset)
            switch token {
            case .leftBrace:
                depth += 1
                parts.append(renderMacroToken(token))
            case .rightBrace:
                if depth == 0 {
                    return parts.joined(separator: " ")
                }
                depth -= 1
                parts.append(renderMacroToken(token))
            case .eof:
                throw ParseError("Unterminated block macro body.")
            default:
                parts.append(renderMacroToken(token))
            }
            offset += 1
        }
    }
}
