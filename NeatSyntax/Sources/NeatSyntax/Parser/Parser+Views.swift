import Foundation

extension Parser {
    mutating func parseLayout() throws -> ViewNode {
        try parseView()
    }

    mutating func parseView() throws -> ViewNode {
        if peek() == .keyword(NeatSyntax.Keyword.ifStatement.rawValue) {
            return try parseViewConditional()
        }
        if peek() == .keyword(NeatSyntax.Keyword.forLoop.rawValue) {
            return try parseViewLoop()
        }
        let invocation = try parseInvocation()
        let base = try lowerInvocationToView(invocation)
        return try parseModifiersIfPresent(for: base)
    }

    mutating func parseViewConditional() throws -> ViewNode {
        var branches: [ViewConditionalBranch] = []

        try consumeKeyword(.ifStatement)
        let condition = try parseExpression()
        let body = try parseViewBlock()
        branches.append(ViewConditionalBranch(condition: condition, body: body))

        while peek() == .keyword(NeatSyntax.Keyword.elseBranch.rawValue) {
            try consumeKeyword(.elseBranch)

            if peek() == .keyword(NeatSyntax.Keyword.ifStatement.rawValue) {
                try consumeKeyword(.ifStatement)
                let elseIfCondition = try parseExpression()
                let elseIfBody = try parseViewBlock()
                branches.append(ViewConditionalBranch(condition: elseIfCondition, body: elseIfBody))
                continue
            }

            let elseBody = try parseViewBlock()
            branches.append(ViewConditionalBranch(condition: nil, body: elseBody))
            break
        }

        return .conditional(branches)
    }

    mutating func parseViewLoop() throws -> ViewNode {
        try consumeKeyword(.forLoop)
        let name = try consumeIdentifier()
        try consumeKeyword(.inKeyword)
        let sequence = try parseExpression()
        try consume(.leftBrace)

        var body: [ViewNode] = []
        while peek() != .rightBrace {
            body.append(try parseView())
        }

        try consume(.rightBrace)
        return .forEach(name: name, sequence: sequence, body: body)
    }

    mutating func parseViewBlock() throws -> [ViewNode] {
        guard peek() == .leftBrace else {
            throw ParseError("Expected block body.")
        }
        try consume(.leftBrace)

        var body: [ViewNode] = []
        while peek() != .rightBrace {
            body.append(try parseView())
        }

        try consume(.rightBrace)
        return body
    }

    mutating func parseInvocation() throws -> Invocation {
        let name = try consumeCallableName()
        let arguments = try parseInvocationArgumentsIfPresent()
        let block = try parseInvocationBlockIfPresent(preferStatements: name == "Button")
        return Invocation(name: name, arguments: arguments, block: block)
    }

    mutating func parseInvocationArgumentsIfPresent() throws -> [CallArgument] {
        guard peek() == .leftParen else { return [] }
        try consume(.leftParen)
        var arguments: [CallArgument] = []

        if peek() != .rightParen {
            while true {
                arguments.append(try parseInvocationArgument())
                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return arguments
    }

    mutating func parseInvocationArgument() throws -> CallArgument {
        if case .identifier(let label) = peek(), peek(offset: 1) == .colon {
            advance()
            try consume(.colon)
            return CallArgument(label: label, value: try parseExpression())
        }
        return CallArgument(label: nil, value: try parseExpression())
    }

    mutating func parseInvocationBlockIfPresent(preferStatements: Bool = false) throws
        -> InvocationBlock?
    {
        guard peek() == .leftBrace else { return nil }
        try consume(.leftBrace)

        if peek() == .rightBrace {
            try consume(.rightBrace)
            return .views([])
        }

        let block: InvocationBlock
        if preferStatements {
            var statements: [Statement] = []
            var localBindings: [String: LocalBindingKind] = [:]
            while peek() != .rightBrace {
                statements.append(
                    try parseStatement(localBindings: &localBindings)
                )
            }
            block = .statements(statements)
        } else {
            var views: [ViewNode] = []
            while peek() != .rightBrace {
                views.append(try parseView())
            }
            block = .views(views)
        }

        try consume(.rightBrace)
        return block
    }

    func lowerInvocationToView(_ invocation: Invocation) throws -> ViewNode {
        switch invocation.name {
        case "Text":
            guard invocation.arguments.count == 1 else {
                throw ParseError("Text requires exactly one argument.")
            }
            guard invocation.arguments[0].label == nil else {
                throw ParseError("Text argument must be a string literal.")
            }
            let content: InterpolatedString
            switch invocation.arguments[0].value {
            case .string(let raw):
                content = parseInterpolatedString(raw)
            case .interpolatedString(let string):
                content = string
            default:
                throw ParseError("Text argument must be a string literal.")
            }
            guard invocation.block == nil else {
                throw ParseError("Text does not accept a trailing block.")
            }
            return .text(content)
        case "Button":
            guard invocation.arguments.count == 1 else {
                throw ParseError("Button requires exactly one argument.")
            }
            guard invocation.arguments[0].label == nil,
                case .string(let title) = invocation.arguments[0].value
            else {
                throw ParseError("Button title must be a string literal.")
            }
            guard case .statements(let action)? = invocation.block else {
                throw ParseError("Button requires an action block.")
            }
            return .button(title: title, action: action)
        case "Div":
            guard invocation.arguments.isEmpty else {
                throw ParseError("Div does not accept arguments.")
            }
            guard case .views(let children)? = invocation.block else {
                throw ParseError("Div requires a view block.")
            }
            return .element(tag: "div", children: children)
        default:
            if invocation.name == "content" {
                guard invocation.arguments.isEmpty, invocation.block == nil else {
                    throw ParseError("content() does not accept arguments or a block.")
                }
                return .slot(name: "content")
            }

            if let block = invocation.block {
                guard case .views(let children) = block else {
                    throw ParseError(
                        "Component '\(invocation.name)' trailing block must contain views."
                    )
                }
                return .component(
                    name: invocation.name,
                    arguments: invocation.arguments,
                    children: children
                )
            }
            return .component(name: invocation.name, arguments: invocation.arguments, children: nil)
        }
    }

    mutating func parseModifiersIfPresent(for view: ViewNode) throws -> ViewNode {
        let modifiers = try parseModifierCalls()

        if modifiers.isEmpty {
            return view
        }
        return .modified(base: view, modifiers: modifiers)
    }

    mutating func parseModifierCalls() throws -> [ModifierCall] {
        var modifiers: [ModifierCall] = []
        while peek() == .dot {
            try consume(.dot)
            let name = try consumeIdentifier()
            let arguments = try parseModifierArgumentListIfPresent()
            modifiers.append(ModifierCall(name: name, arguments: arguments))
        }
        return modifiers
    }

    mutating func parseModifierArgumentListIfPresent() throws -> [ModifierCallArgument] {
        guard peek() == .leftParen else {
            return []
        }

        try consume(.leftParen)
        if peek() == .rightParen {
            try consume(.rightParen)
            return []
        }

        var arguments: [ModifierCallArgument] = []
        while true {
            arguments.append(try parseModifierCallArgument())
            guard peek() == .comma else { break }
            advance()
        }
        try consume(.rightParen)
        return arguments
    }

    mutating func parseModifierCallArgument() throws -> ModifierCallArgument {
        if case .identifier(let label) = peek(), peek(offset: 1) == .colon {
            advance()
            try consume(.colon)
            return ModifierCallArgument(label: label, value: try parseModifierArgument())
        }
        return ModifierCallArgument(label: nil, value: try parseModifierArgument())
    }

    mutating func parseModifierArgument() throws -> ModifierArgument {
        switch peek() {
        case .dot:
            try consume(.dot)
            let name = try consumeIdentifier()
            if peek() == .leftParen {
                let arguments = try parseModifierCallArguments()
                try validateModifierFunctionCall(name: name, arguments: arguments)
                return .enumCall(name: name, arguments: arguments)
            }
            return .enumCase(name)
        case .stringLiteral(let value):
            advance()
            return .string(value)
        case .integer(let value):
            advance()
            return .integer(value)
        case .identifier(let value):
            advance()
            return .identifier(value)
        default:
            throw ParseError("Expected modifier argument.")
        }
    }

    mutating func parseModifierCallArguments() throws -> [ModifierArgument] {
        try consume(.leftParen)
        var arguments: [ModifierArgument] = []

        if peek() != .rightParen {
            while true {
                arguments.append(try parseModifierArgument())
                guard peek() == .comma else { break }
                advance()
            }
        }

        try consume(.rightParen)
        return arguments
    }

    func validateModifierFunctionCall(name: String, arguments: [ModifierArgument]) throws {
        switch name.lowercased() {
        case "rgba":
            guard arguments.count == 4 else {
                throw ParseError("rgba expects 4 arguments: red, green, blue, alpha.")
            }
            try validateRGBChannel(arguments[0], label: "red")
            try validateRGBChannel(arguments[1], label: "green")
            try validateRGBChannel(arguments[2], label: "blue")
            try validateAlpha(arguments[3], function: "rgba")
        case "rgb":
            guard arguments.count == 3 else {
                throw ParseError("rgb expects 3 arguments: red, green, blue.")
            }
            try validateRGBChannel(arguments[0], label: "red")
            try validateRGBChannel(arguments[1], label: "green")
            try validateRGBChannel(arguments[2], label: "blue")
        case "hsla":
            guard arguments.count == 4 else {
                throw ParseError("hsla expects 4 arguments: hue, saturation, lightness, alpha.")
            }
            try validateAlpha(arguments[3], function: "hsla")
        case "oklch":
            guard (3...4).contains(arguments.count) else {
                throw ParseError("oklch expects 3 or 4 arguments.")
            }
            if arguments.count == 4 {
                try validateAlpha(arguments[3], function: "oklch")
            }
        default:
            break
        }
    }

    func validateRGBChannel(_ argument: ModifierArgument, label: String) throws {
        let byteRange: ClosedRange<Double> = 0...255
        let percentRange: ClosedRange<Double> = 0...100

        switch argument {
        case .integer(let value):
            guard byteRange.contains(Double(value)) else {
                throw ParseError("\(label) must be in 0...255.")
            }
        case .double(let value):
            guard byteRange.contains(value) else {
                throw ParseError("\(label) must be in 0...255.")
            }
        case .percentage(let value):
            guard percentRange.contains(value) else {
                throw ParseError("\(label)% must be in 0...100%.")
            }
        default:
            break
        }
    }

    func validateAlpha(_ argument: ModifierArgument, function: String) throws {
        let unitRange: ClosedRange<Double> = 0...1
        let percentRange: ClosedRange<Double> = 0...100

        switch argument {
        case .integer(let value):
            let alpha = Double(value)
            guard unitRange.contains(alpha) else {
                throw ParseError("\(function) alpha must be in 0...1 or 0...100%.")
            }
        case .double(let value):
            guard unitRange.contains(value) else {
                throw ParseError("\(function) alpha must be in 0...1 or 0...100%.")
            }
        case .percentage(let value):
            guard percentRange.contains(value) else {
                throw ParseError("\(function) alpha% must be in 0...100%.")
            }
        default:
            break
        }
    }

    func parseInterpolatedString(_ value: String) -> InterpolatedString {
        var segments: [StringSegment] = []
        var cursor = value.startIndex

        while let interpolationStart = value[cursor...].range(of: "\\(") {
            let literal = String(value[cursor..<interpolationStart.lowerBound])
            if !literal.isEmpty {
                segments.append(.text(literal))
            }

            let expressionStart = interpolationStart.upperBound
            guard let expressionEnd = findInterpolationEnd(in: value, startingAt: expressionStart)
            else {
                segments.append(.text(String(value[interpolationStart.lowerBound...])))
                return InterpolatedString(segments: segments)
            }

            let expressionText = value[expressionStart..<expressionEnd].trimmingCharacters(
                in: .whitespacesAndNewlines)
            segments.append(.expression(parseInterpolationExpression(expressionText)))
            cursor = value.index(after: expressionEnd)
        }

        let remaining = String(value[cursor...])
        if !remaining.isEmpty {
            segments.append(.text(remaining))
        }

        return InterpolatedString(segments: segments)
    }

    func findInterpolationEnd(in value: String, startingAt start: String.Index) -> String.Index? {
        var cursor = start
        var depth = 1
        var inString = false
        var stringEscape = false

        while cursor < value.endIndex {
            let character = value[cursor]

            if inString {
                if stringEscape {
                    stringEscape = false
                } else if character == "\\" {
                    stringEscape = true
                } else if character == "\"" {
                    inString = false
                }

                cursor = value.index(after: cursor)
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            default:
                break
            }

            cursor = value.index(after: cursor)
        }

        return nil
    }

    func parseInterpolationExpression(_ source: String) -> Expression {
        guard !source.isEmpty else {
            return .string("")
        }

        do {
            var parser = try Parser(source: source)
            let expression = try parser.parseExpression()
            try parser.consume(.eof)
            return expression
        } catch {
            return .identifier(source)
        }
    }
}
