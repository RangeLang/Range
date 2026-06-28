import RangeCompiler

enum StringyStatementRecord {
    case returnStatement(value: Expression?, llvm: String)
    case member(kind: String, name: String, type: TypeReference, value: Expression)
    case assignment(target: String, value: Expression)
    case expression(Expression)
    case whileLoop(condition: Expression, body: [StringyStatementRecord])
    case conditional(condition: Expression, body: [StringyStatementRecord])
    case breakStatement
    case continueStatement

    static func records(in text: String) -> [StringyStatementRecord] {
        parseLines(Array(text.split(separator: "\n", omittingEmptySubsequences: false)))
    }

    static func first(in text: String) -> StringyStatementRecord? {
        records(in: text).first
    }

    static func returnLLVM(in text: String) -> String? {
        for record in records(in: text) {
            if case .returnStatement(_, let llvm) = record {
                return llvm
            }
        }
        return nil
    }

    private static func parseLines(_ lines: [Substring]) -> [StringyStatementRecord] {
        guard let first = lines.first else { return [] }
        let firstLine = String(first)
        guard let parent = parseLine(firstLine) else {
            return lines.compactMap { parseLine(String($0)) }
        }

        let children = parseLines(Array(lines.dropFirst()))
        switch parent {
        case .whileLoop(let condition, _):
            return [.whileLoop(condition: condition, body: children)]
        case .conditional(let condition, _):
            return [.conditional(condition: condition, body: children)]
        default:
            return [parent] + children
        }
    }

    private static func parseLine(_ line: String) -> StringyStatementRecord? {
        guard (line.hasPrefix("statement|") || line.hasPrefix("member|")),
            let kind = field("kind", in: line)
        else {
            return nil
        }

        switch kind {
        case "return":
            guard let llvm = field("llvm", in: line), llvm.hasPrefix("ret ") else {
                return nil
            }
            let value = field("value", in: line).flatMap(parseExpression)
            return .returnStatement(value: value, llvm: llvm)
        case "let", "state":
            guard let name = field("name", in: line),
                let typeText = field("type", in: line),
                let valueText = field("value", in: line),
                let type = parseTypeReference(typeText),
                let value = parseExpression(valueText)
            else {
                return nil
            }
            return .member(
                kind: kind,
                name: name,
                type: type,
                value: value
            )
        case "assign":
            guard let target = field("target", in: line),
                let valueText = field("value", in: line),
                let value = parseExpression(valueText)
            else {
                return nil
            }
            return .assignment(target: target, value: value)
        case "expression":
            guard let valueText = field("value", in: line),
                let value = parseExpression(valueText)
            else {
                return nil
            }
            return .expression(value)
        case "while":
            guard let conditionText = field("condition", in: line),
                let condition = parseExpression(conditionText)
            else {
                return nil
            }
            return .whileLoop(condition: condition, body: [])
        case "if":
            guard let conditionText = field("condition", in: line),
                let condition = parseExpression(conditionText)
            else {
                return nil
            }
            return .conditional(condition: condition, body: [])
        case "break":
            return .breakStatement
        case "continue":
            return .continueStatement
        default:
            return nil
        }
    }

    private static func parseExpression(_ text: String) -> Expression? {
        if text == "true" {
            return .boolean(true)
        }
        if text == "false" {
            return .boolean(false)
        }
        do {
            var parser = try Parser(source: text)
            return try parser.parseExpression()
        } catch {
            return nil
        }
    }

    private static func parseTypeReference(_ text: String) -> TypeReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("Array<"), trimmed.hasSuffix(">") {
            let inner = String(trimmed.dropFirst("Array<".count).dropLast())
            return parseTypeReference(inner).map(TypeReference.array)
        }
        guard let genericStart = trimmed.firstIndex(of: "<"), trimmed.hasSuffix(">") else {
            return .named(trimmed)
        }
        let baseName = String(trimmed[..<genericStart])
        let argumentsText = String(trimmed[trimmed.index(after: genericStart)..<trimmed.index(before: trimmed.endIndex)])
        let arguments = splitGenericArguments(argumentsText).compactMap(parseTypeReference)
        guard arguments.count == splitGenericArguments(argumentsText).count else {
            return nil
        }
        return .generic(base: .named(baseName), arguments: arguments)
    }

    private static func splitGenericArguments(_ text: String) -> [String] {
        var arguments: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            switch character {
            case "<":
                depth += 1
                current.append(character)
            case ">":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                arguments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.isEmpty {
            arguments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return arguments
    }

    private static func field(_ name: String, in line: String) -> String? {
        let prefix = "\(name)="
        guard let range = line.range(of: prefix) else {
            return nil
        }
        let afterPrefix = line[range.upperBound...]
        if let end = afterPrefix.firstIndex(of: "|") {
            return String(afterPrefix[..<end])
        }
        return String(afterPrefix)
    }
}
