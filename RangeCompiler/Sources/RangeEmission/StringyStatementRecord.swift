import RangeCompiler

enum StringyStatementRecord {
    case returnStatement(value: Expression?, llvm: String)
    case member(kind: String, name: String, type: TypeReference, value: Expression)
    case assignment(target: String, value: Expression)
    case expression(Expression)
    case whileLoop(condition: Expression, body: [StringyStatementRecord])
    case conditional([StringyConditionalBranch])
    case breakStatement
    case continueStatement

    static func records(in text: String) -> [StringyStatementRecord] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.contains(where: hasExplicitBlockMarker) else {
            return parseLines(lines)
        }

        var index = 0
        return parseExplicitBlock(lines, index: &index)
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

    private static func parseLines(_ lines: [String]) -> [StringyStatementRecord] {
        guard let first = lines.first else { return [] }
        guard let parent = parseLine(first) else {
            return lines.compactMap(parseLine)
        }

        let children = parseLines(Array(lines.dropFirst()))
        switch parent {
        case .whileLoop(let condition, _):
            return [.whileLoop(condition: condition, body: children)]
        case .conditional(let branches):
            guard let first = branches.first else {
                return []
            }
            return [
                .conditional([
                    StringyConditionalBranch(condition: first.condition, body: children)
                ])
            ]
        default:
            return [parent] + children
        }
    }

    private static func parseExplicitBlock(
        _ lines: [String],
        index: inout Int
    ) -> [StringyStatementRecord] {
        var records: [StringyStatementRecord] = []
        while index < lines.count {
            let line = lines[index]
            guard let kind = field("kind", in: line) else {
                index += 1
                continue
            }
            if kind == "end" || kind == "else" {
                break
            }

            switch kind {
            case "while":
                guard let condition = field("condition", in: line).flatMap(parseExpression) else {
                    index += 1
                    continue
                }
                index += 1
                let body = parseExplicitBlock(lines, index: &index)
                consumeEnd(lines, index: &index)
                records.append(.whileLoop(condition: condition, body: body))
            case "if":
                guard let condition = field("condition", in: line).flatMap(parseExpression) else {
                    index += 1
                    continue
                }
                index += 1
                let trueBody = parseExplicitBlock(lines, index: &index)
                var branches = [StringyConditionalBranch(condition: condition, body: trueBody)]
                if index < lines.count, field("kind", in: lines[index]) == "else" {
                    index += 1
                    branches.append(
                        StringyConditionalBranch(
                            condition: nil,
                            body: parseExplicitBlock(lines, index: &index)
                        )
                    )
                }
                consumeEnd(lines, index: &index)
                records.append(.conditional(branches))
            default:
                if let record = parseLine(line) {
                    records.append(record)
                }
                index += 1
            }
        }
        return records
    }

    private static func consumeEnd(_ lines: [String], index: inout Int) {
        guard index < lines.count, field("kind", in: lines[index]) == "end" else {
            return
        }
        index += 1
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
            return .conditional([
                StringyConditionalBranch(condition: condition, body: [])
            ])
        case "end", "else":
            return nil
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
            return normalizeBooleanIdentifiers(try parser.parseExpression())
        } catch {
            return nil
        }
    }

    private static func normalizeBooleanIdentifiers(_ expression: Expression) -> Expression {
        switch expression {
        case .identifier("true"):
            return .boolean(true)
        case .identifier("false"):
            return .boolean(false)
        case .call(let name, let arguments):
            return .call(
                name: name,
                arguments: arguments.map {
                    CallArgument(label: $0.label, value: normalizeBooleanIdentifiers($0.value))
                }
            )
        case .array(let elements):
            return .array(elements.map(normalizeBooleanIdentifiers))
        case .dictionary(let elements):
            return .dictionary(
                elements.map {
                    DictionaryElement(
                        key: normalizeBooleanIdentifiers($0.key),
                        value: normalizeBooleanIdentifiers($0.value)
                    )
                }
            )
        case .ternary(let condition, let trueExpression, let falseExpression):
            return .ternary(
                condition: normalizeBooleanIdentifiers(condition),
                trueExpression: normalizeBooleanIdentifiers(trueExpression),
                falseExpression: normalizeBooleanIdentifiers(falseExpression)
            )
        case .unary(let operatorSymbol, let nested):
            return .unary(
                operatorSymbol: operatorSymbol,
                expression: normalizeBooleanIdentifiers(nested)
            )
        case .binary(let lhs, let operatorSymbol, let rhs):
            return .binary(
                lhs: normalizeBooleanIdentifiers(lhs),
                operatorSymbol: operatorSymbol,
                rhs: normalizeBooleanIdentifiers(rhs)
            )
        case .block, .bindingReference, .boolean, .double, .integer, .macroInvocation, .nilLiteral,
            .string, .identifier:
            return expression
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

struct StringyConditionalBranch {
    let condition: Expression?
    let body: [StringyStatementRecord]
}

private func hasExplicitBlockMarker(_ line: String) -> Bool {
    let kindPrefix = "kind="
    guard let range = line.range(of: kindPrefix) else {
        return false
    }
    let afterPrefix = line[range.upperBound...]
    let kind =
        afterPrefix.firstIndex(of: "|").map { String(afterPrefix[..<$0]) }
        ?? String(afterPrefix)
    return kind == "end" || kind == "else"
}
